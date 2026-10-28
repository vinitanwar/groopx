package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
)

func searchUsers(c *gin.Context) {
	query := strings.TrimSpace(c.Query("q"))
	if len(query) < 2 { c.JSON(http.StatusOK, gin.H{"items": []gin.H{}}); return }
	phoneDigits := contactPhoneDigits(query)
	if len(phoneDigits) == 11 && phoneDigits[0] == '0' { phoneDigits = phoneDigits[1:] }
	if len(phoneDigits) < 7 { phoneDigits = "" }
	rows, err := db.Query(c.Request.Context(), `SELECT id::text, COALESCE(full_name,username,'GroopX User'), COALESCE(username,''), avatar_url
		FROM users WHERE id<>$1 AND account_status='active' AND NOT EXISTS(SELECT 1 FROM user_blocks b WHERE (b.blocker_id=$1 AND b.blocked_id=users.id) OR (b.blocker_id=users.id AND b.blocked_id=$1))
		AND (username ILIKE $2 OR full_name ILIKE $2 OR ($3<>'' AND (REGEXP_REPLACE(phone,'[^0-9]','','g')=$3 OR (LENGTH($3)=10 AND RIGHT(REGEXP_REPLACE(phone,'[^0-9]','','g'),10)=$3))))
		ORDER BY full_name NULLS LAST LIMIT 20`, c.GetString("user_id"), "%"+query+"%", phoneDigits)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"search unavailable"}); return }
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() { var id,name,username string; var avatar *string; if rows.Scan(&id,&name,&username,&avatar)==nil { items=append(items,gin.H{"id":id,"name":name,"username":username,"avatar_url":avatar}) } }
	c.JSON(http.StatusOK, gin.H{"items":items})
}

func discoverContacts(c *gin.Context) {
	var input struct {
		Phones []string `json:"phones"`
	}
	if c.ShouldBindJSON(&input) != nil || len(input.Phones) == 0 || len(input.Phones) > 500 {
		c.JSON(http.StatusBadRequest, gin.H{"error":"provide between 1 and 500 phone numbers"})
		return
	}
	exactSet, suffixSet := make(map[string]struct{}), make(map[string]struct{})
	for _, raw := range input.Phones {
		digits := contactPhoneDigits(raw)
		if len(digits) < 7 || len(digits) > 15 { continue }
		exactSet[digits] = struct{}{}
		if strings.HasPrefix(digits, "00") && len(digits) > 9 {
			exactSet[digits[2:]] = struct{}{}
		}
		// Use suffix matching only for local numbers. Fully qualified numbers
		// must match exactly so identical national numbers in other countries
		// are not accidentally disclosed.
		if len(digits) == 10 {
			suffixSet[digits] = struct{}{}
		} else if len(digits) == 11 && digits[0] == '0' {
			suffixSet[digits[1:]] = struct{}{}
		}
	}
	if len(exactSet) == 0 {
		c.JSON(http.StatusOK, gin.H{"items": []gin.H{}})
		return
	}
	exact := make([]string, 0, len(exactSet))
	for value := range exactSet { exact = append(exact, value) }
	suffixes := make([]string, 0, len(suffixSet))
	for value := range suffixSet { suffixes = append(suffixes, value) }
	rows, err := db.Query(c.Request.Context(), `WITH discoverable AS (
		SELECT id,full_name,username,avatar_url,REGEXP_REPLACE(phone,'[^0-9]','','g') AS digits
		FROM users WHERE id<>$1 AND account_status='active'
		AND NOT EXISTS(SELECT 1 FROM user_blocks b WHERE (b.blocker_id=$1 AND b.blocked_id=users.id) OR (b.blocker_id=users.id AND b.blocked_id=$1))
	) SELECT id::text,COALESCE(full_name,username,'GroopX User'),COALESCE(username,''),avatar_url
	FROM discoverable WHERE digits=ANY($2::text[]) OR (LENGTH(digits)>=10 AND RIGHT(digits,10)=ANY($3::text[]))
	ORDER BY full_name NULLS LAST LIMIT 500`, c.GetString("user_id"), exact, suffixes)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error":"phone contacts could not be matched"})
		return
	}
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var id, name, username string
		var avatar *string
		if rows.Scan(&id, &name, &username, &avatar) == nil {
			items = append(items, gin.H{"id":id,"name":name,"username":username,"avatar_url":avatar})
		}
	}
	c.JSON(http.StatusOK, gin.H{"items":items})
}

func contactPhoneDigits(value string) string {
	var normalized strings.Builder
	for _, character := range value {
		if character >= '0' && character <= '9' { normalized.WriteRune(character) }
	}
	return normalized.String()
}

func listContacts(c *gin.Context) {
	rows, err := db.Query(c.Request.Context(), `SELECT ct.display_name, COALESCE(ct.phone,''), COALESCE(ct.username,''), COALESCE(ct.notes,''), ct.contact_user_id::text, u.avatar_url
		FROM contacts ct LEFT JOIN users u ON u.id=ct.contact_user_id WHERE ct.owner_id=$1 ORDER BY ct.display_name`, c.GetString("user_id"))
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"contacts could not be loaded"}); return }
	defer rows.Close(); items:=make([]gin.H,0)
	for rows.Next() { var name,phone,username,notes string; var contactID,avatar *string; if rows.Scan(&name,&phone,&username,&notes,&contactID,&avatar)==nil { items=append(items,gin.H{"display_name":name,"phone":phone,"username":username,"contact_user_id":contactID,"avatar_url":avatar,"notes":notes}) } }
	c.JSON(http.StatusOK,gin.H{"items":items})
}

func createContact(c *gin.Context) {
	ownerID:=c.GetString("user_id")
	var input struct { ContactUserID string `json:"contact_user_id" binding:"omitempty,uuid"`; DisplayName string `json:"display_name" binding:"required,max=120"`; Phone string `json:"phone" binding:"omitempty,max=20"`; Username string `json:"username" binding:"omitempty,max=40"`; Notes string `json:"notes" binding:"omitempty,max=100"` }
	if c.ShouldBindJSON(&input)!=nil || (strings.TrimSpace(input.ContactUserID)=="" && strings.TrimSpace(input.Phone)=="" && strings.TrimSpace(input.Username)=="") { c.JSON(http.StatusBadRequest,gin.H{"error":"name and a GroopX user are required"}); return }
	ctx:=c.Request.Context(); tx,err:=db.Begin(ctx); if err!=nil { c.JSON(http.StatusInternalServerError,gin.H{"error":"contact could not be saved"}); return }; defer tx.Rollback(ctx)
	var contactUserID string
	if strings.TrimSpace(input.ContactUserID)!="" {
		err=tx.QueryRow(ctx,`SELECT id::text FROM users WHERE id=$1 AND account_status='active'`,strings.TrimSpace(input.ContactUserID)).Scan(&contactUserID)
	} else {
		err=tx.QueryRow(ctx,`SELECT id::text FROM users WHERE account_status='active' AND (($1<>'' AND phone=$1) OR ($2<>'' AND LOWER(username)=LOWER($2))) LIMIT 1`,strings.TrimSpace(input.Phone),strings.TrimPrefix(strings.TrimSpace(input.Username),"@")).Scan(&contactUserID)
	}
	if errors.Is(err,pgx.ErrNoRows) { c.JSON(http.StatusNotFound,gin.H{"error":"GroopX user not found"}); return }
	if err!=nil || contactUserID==ownerID { c.JSON(http.StatusBadRequest,gin.H{"error":"invalid contact"}); return }
	if usersBlocked(ownerID,contactUserID) { c.JSON(http.StatusForbidden,gin.H{"error":"contact cannot be added because communication is blocked"}); return }
	command,err:=tx.Exec(ctx,`UPDATE contacts SET phone=NULLIF($3,''),username=NULLIF($4,''),notes=NULLIF($5,'')
		WHERE owner_id=$1 AND contact_user_id=$2`,ownerID,contactUserID,strings.TrimSpace(input.Phone),strings.TrimPrefix(strings.TrimSpace(input.Username),"@"),strings.TrimSpace(input.Notes))
	if err==nil && command.RowsAffected()==0 {
		_,err=tx.Exec(ctx,`INSERT INTO contacts(owner_id,contact_user_id,display_name,phone,username,notes) VALUES($1,$2,$3,NULLIF($4,''),NULLIF($5,''),NULLIF($6,''))
			ON CONFLICT(owner_id,display_name) DO UPDATE SET contact_user_id=EXCLUDED.contact_user_id,phone=EXCLUDED.phone,username=EXCLUDED.username,notes=EXCLUDED.notes`,ownerID,contactUserID,strings.TrimSpace(input.DisplayName),strings.TrimSpace(input.Phone),strings.TrimPrefix(strings.TrimSpace(input.Username),"@"),strings.TrimSpace(input.Notes))
	}
	if err!=nil { c.JSON(http.StatusConflict,gin.H{"error":"contact could not be saved"}); return }
	conversationID,err:=ensureDirectConversation(ctx,tx,ownerID,contactUserID); if err!=nil { c.JSON(http.StatusInternalServerError,gin.H{"error":"direct chat could not be created"}); return }
	if tx.Commit(ctx)!=nil { c.JSON(http.StatusInternalServerError,gin.H{"error":"contact could not be committed"}); return }
	c.JSON(http.StatusCreated,gin.H{"contact_user_id":contactUserID,"conversation_id":conversationID,"display_name":input.DisplayName})
}

func ensureDirectConversation(ctx context.Context, tx pgx.Tx, firstID, secondID string) (string,error) {
	var id string
	err:=tx.QueryRow(ctx,`SELECT c.id::text FROM conversations c JOIN conversation_members cm ON cm.conversation_id=c.id
		WHERE c.kind='direct' AND cm.user_id IN ($1,$2) GROUP BY c.id HAVING COUNT(*)=2 AND COUNT(*) FILTER (WHERE cm.user_id IN ($1,$2))=2 LIMIT 1`,firstID,secondID).Scan(&id)
	if err==nil { return id,nil }; if !errors.Is(err,pgx.ErrNoRows) { return "",err }
	err=tx.QueryRow(ctx,`INSERT INTO conversations(kind,created_by) VALUES('direct',$1) RETURNING id::text`,firstID).Scan(&id); if err!=nil{return "",err}
	_,err=tx.Exec(ctx,`INSERT INTO conversation_members(conversation_id,user_id,role) VALUES($1,$2,'member'),($1,$3,'member')`,id,firstID,secondID)
	return id,err
}

func createGroup(c *gin.Context) {
	creatorID:=c.GetString("user_id")
	var input struct { Name string `json:"name" binding:"required,max=50"`; Description string `json:"description" binding:"omitempty,max=200"`; Privacy string `json:"privacy" binding:"required,oneof=private public"`; MemberIDs []string `json:"member_ids" binding:"required,min=1"`; AnnouncementOnly bool `json:"announcement_only"`; JoinApprovalRequired bool `json:"join_approval_required"`; MembersCanEditInfo bool `json:"members_can_edit_info"`; MembersCanAddMembers bool `json:"members_can_add_members"` }
	if c.ShouldBindJSON(&input)!=nil { c.JSON(http.StatusBadRequest,gin.H{"error":"invalid group"}); return }
	ctx:=c.Request.Context(); tx,err:=db.Begin(ctx); if err!=nil { c.JSON(http.StatusInternalServerError,gin.H{"error":"group could not be created"}); return }; defer tx.Rollback(ctx)
	var id string; err=tx.QueryRow(ctx,`INSERT INTO conversations(kind,title,description,privacy,created_by,announcement_only,join_approval_required,members_can_edit_info,members_can_add_members) VALUES('group',$1,$2,$3,$4,$5,$6,$7,$8) RETURNING id::text`,strings.TrimSpace(input.Name),strings.TrimSpace(input.Description),input.Privacy,creatorID,input.AnnouncementOnly,input.JoinApprovalRequired,input.MembersCanEditInfo,input.MembersCanAddMembers).Scan(&id)
	if err!=nil { c.JSON(http.StatusInternalServerError,gin.H{"error":"group could not be created"}); return }
	_,err=tx.Exec(ctx,`INSERT INTO conversation_members(conversation_id,user_id,role) VALUES($1,$2,'admin')`,id,creatorID); if err!=nil { c.JSON(http.StatusInternalServerError,gin.H{"error":"group creator could not be added"}); return }
	for _,memberID:=range input.MemberIDs { if memberID==creatorID {continue}; if _,err=tx.Exec(ctx,`INSERT INTO conversation_members(conversation_id,user_id,role) VALUES($1,$2,'member') ON CONFLICT DO NOTHING`,id,memberID); err!=nil { c.JSON(http.StatusBadRequest,gin.H{"error":"one or more members are invalid"}); return } }
	creatorName,err:=groupActivityUserName(ctx,tx,id,creatorID);if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"group activity could not be saved"});return}
	activity,err:=recordGroupActivity(ctx,tx,id,"group_created",creatorID,"",groupActivityText("group_created",creatorName,"",""));if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"group activity could not be saved"});return}
	if tx.Commit(ctx)!=nil { c.JSON(http.StatusInternalServerError,gin.H{"error":"group could not be saved"}); return }
	publishGroupActivity(&activity)
	c.JSON(http.StatusCreated,gin.H{"id":id,"name":input.Name,"privacy":input.Privacy,"announcement_only":input.AnnouncementOnly,"join_approval_required":input.JoinApprovalRequired,"members_can_edit_info":input.MembersCanEditInfo,"members_can_add_members":input.MembersCanAddMembers,"admin":true,"can_edit_info":true,"can_add_members":true})
}

func getGroup(c *gin.Context) {
	id,userID:=c.Param("id"),c.GetString("user_id"); if !isConversationMember(c,id,userID){c.JSON(http.StatusForbidden,gin.H{"error":"not a group member"});return}
	var name,description,privacy string; var avatarURL *string; var announcementOnly,joinApprovalRequired,membersCanEditInfo,membersCanAddMembers bool; err:=db.QueryRow(c.Request.Context(),`SELECT title,COALESCE(description,''),COALESCE(privacy::text,'private'),avatar_url,COALESCE(announcement_only,FALSE),COALESCE(join_approval_required,FALSE),COALESCE(members_can_edit_info,FALSE),COALESCE(members_can_add_members,FALSE) FROM conversations WHERE id=$1 AND kind IN ('group','community') AND deleted_at IS NULL`,id).Scan(&name,&description,&privacy,&avatarURL,&announcementOnly,&joinApprovalRequired,&membersCanEditInfo,&membersCanAddMembers)
	if err!=nil { c.JSON(http.StatusNotFound,gin.H{"error":"group not found"});return }
	rows,err:=db.Query(c.Request.Context(),`SELECT u.id::text,COALESCE(NULLIF(cm.group_display_name,''),NULLIF(u.full_name,''),NULLIF(u.username,''),'GroopX member'),COALESCE(NULLIF(u.full_name,''),NULLIF(u.username,''),'GroopX member'),COALESCE(cm.group_display_name,''),COALESCE(u.username,''),COALESCE(u.avatar_url,''),cm.role,u.account_status FROM conversation_members cm JOIN users u ON u.id=cm.user_id WHERE cm.conversation_id=$1 ORDER BY (cm.role='admin') DESC,LOWER(COALESCE(NULLIF(cm.group_display_name,''),NULLIF(u.full_name,''),NULLIF(u.username,''),'GroopX member'))`,id)
	if err!=nil { c.JSON(http.StatusInternalServerError,gin.H{"error":"members could not be loaded"});return}; defer rows.Close(); members:=make([]gin.H,0);myRole:="member"
	for rows.Next(){var memberID,memberName,profileName,displayName,username,avatarURL,role,accountStatus string;if rows.Scan(&memberID,&memberName,&profileName,&displayName,&username,&avatarURL,&role,&accountStatus)==nil{mine:=memberID==userID;if mine{myRole=role};mention:="";if accountStatus=="active"{mention=mentionHandle(memberID,profileName,username)};members=append(members,gin.H{"id":memberID,"name":memberName,"profile_name":profileName,"display_name":displayName,"username":username,"avatar_url":avatarURL,"mention":mention,"role":role,"mine":mine})}}
	rows.Close()
	pendingRequests:=pendingGroupJoinRequestCount(c.Request.Context(),id,userID)
	c.JSON(http.StatusOK,gin.H{"id":id,"name":name,"description":description,"privacy":privacy,"avatar_url":avatarURL,"announcement_only":announcementOnly,"join_approval_required":joinApprovalRequired,"members_can_edit_info":membersCanEditInfo,"members_can_add_members":membersCanAddMembers,"admin":myRole=="admin","can_edit_info":groupCanEditInfo(myRole,membersCanEditInfo),"can_add_members":groupCanAddMembers(myRole,membersCanAddMembers),"pending_join_requests":pendingRequests,"members":members})
}

func updateGroup(c *gin.Context) {
	groupID,userID:=c.Param("id"),c.GetString("user_id")
	var input struct{Name string `json:"name" binding:"required,max=50"`;Description string `json:"description" binding:"omitempty,max=200"`;Privacy string `json:"privacy" binding:"required,oneof=private public"`;AnnouncementOnly *bool `json:"announcement_only"`;JoinApprovalRequired *bool `json:"join_approval_required"`;MembersCanEditInfo *bool `json:"members_can_edit_info"`;MembersCanAddMembers *bool `json:"members_can_add_members"`}
	if c.ShouldBindJSON(&input)!=nil||len(strings.TrimSpace(input.Name))<2{c.JSON(http.StatusBadRequest,gin.H{"error":"valid group name and privacy are required"});return}
	ctx:=c.Request.Context();tx,err:=db.Begin(ctx);if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"group could not be updated"});return};defer tx.Rollback(ctx)
	var oldName,oldDescription,oldPrivacy,role string;var oldAnnouncementOnly,oldJoinApprovalRequired,oldMembersCanEditInfo,oldMembersCanAddMembers bool
	err=tx.QueryRow(ctx,`SELECT conversation.title,COALESCE(conversation.description,''),COALESCE(conversation.privacy::text,'private'),COALESCE(conversation.announcement_only,FALSE),COALESCE(conversation.join_approval_required,FALSE),COALESCE(conversation.members_can_edit_info,FALSE),COALESCE(conversation.members_can_add_members,FALSE),member.role
		FROM conversations conversation JOIN conversation_members member ON member.conversation_id=conversation.id AND member.user_id=$2
		WHERE conversation.id=$1 AND conversation.kind='group' AND conversation.deleted_at IS NULL FOR UPDATE OF conversation,member`,groupID,userID).Scan(&oldName,&oldDescription,&oldPrivacy,&oldAnnouncementOnly,&oldJoinApprovalRequired,&oldMembersCanEditInfo,&oldMembersCanAddMembers,&role)
	if errors.Is(err,pgx.ErrNoRows){c.JSON(http.StatusForbidden,gin.H{"error":"group info editing is restricted to admins"});return}
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"group could not be updated"});return}
	if !groupCanEditInfo(role,oldMembersCanEditInfo){c.JSON(http.StatusForbidden,gin.H{"error":"group info editing is restricted to admins"});return}
	announcementOnly,joinApprovalRequired:=oldAnnouncementOnly,oldJoinApprovalRequired
	membersCanEditInfo,membersCanAddMembers:=oldMembersCanEditInfo,oldMembersCanAddMembers
	if input.AnnouncementOnly!=nil{announcementOnly=*input.AnnouncementOnly}
	if input.JoinApprovalRequired!=nil{joinApprovalRequired=*input.JoinApprovalRequired}
	if input.MembersCanEditInfo!=nil{membersCanEditInfo=*input.MembersCanEditInfo}
	if input.MembersCanAddMembers!=nil{membersCanAddMembers=*input.MembersCanAddMembers}
	if role!="admin"&&(input.Privacy!=oldPrivacy||announcementOnly!=oldAnnouncementOnly||joinApprovalRequired!=oldJoinApprovalRequired||membersCanEditInfo!=oldMembersCanEditInfo||membersCanAddMembers!=oldMembersCanAddMembers){c.JSON(http.StatusForbidden,gin.H{"error":"only admins can change group permissions and privacy"});return}
	err=tx.QueryRow(ctx,`UPDATE conversations SET title=$2,description=NULLIF($3,''),privacy=$4,announcement_only=$5,join_approval_required=$6,members_can_edit_info=$7,members_can_add_members=$8,updated_at=NOW() WHERE id=$1 RETURNING announcement_only,join_approval_required,members_can_edit_info,members_can_add_members`,groupID,strings.TrimSpace(input.Name),strings.TrimSpace(input.Description),input.Privacy,announcementOnly,joinApprovalRequired,membersCanEditInfo,membersCanAddMembers).Scan(&announcementOnly,&joinApprovalRequired,&membersCanEditInfo,&membersCanAddMembers)
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"group could not be updated"});return}
	actorName,err:=groupActivityUserName(ctx,tx,groupID,userID);if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"group activity could not be saved"});return}
	activities:=make([]groupActivityMessage,0,4)
	appendActivity:=func(event,detail string)bool{activity,activityErr:=recordGroupActivity(ctx,tx,groupID,event,userID,"",groupActivityText(event,actorName,"",detail));if activityErr!=nil{return false};activities=append(activities,activity);return true}
	name:=strings.TrimSpace(input.Name);description:=strings.TrimSpace(input.Description)
	if name!=oldName&&!appendActivity("group_renamed",name){c.JSON(http.StatusInternalServerError,gin.H{"error":"group activity could not be saved"});return}
	if announcementOnly!=oldAnnouncementOnly{event:="announcement_disabled";if announcementOnly{event="announcement_enabled"};if !appendActivity(event,""){c.JSON(http.StatusInternalServerError,gin.H{"error":"group activity could not be saved"});return}}
	if description!=oldDescription||input.Privacy!=oldPrivacy||joinApprovalRequired!=oldJoinApprovalRequired{if !appendActivity("group_settings_updated",""){c.JSON(http.StatusInternalServerError,gin.H{"error":"group activity could not be saved"});return}}
	if membersCanEditInfo!=oldMembersCanEditInfo||membersCanAddMembers!=oldMembersCanAddMembers{if !appendActivity("group_permissions_updated",""){c.JSON(http.StatusInternalServerError,gin.H{"error":"group activity could not be saved"});return}}
	if tx.Commit(ctx)!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"group could not be updated"});return}
	for index:=range activities{publishGroupActivity(&activities[index])}
	broadcast(groupID,userID,gin.H{"type":"group_settings_update","conversation_id":groupID,"announcement_only":announcementOnly,"join_approval_required":joinApprovalRequired,"members_can_edit_info":membersCanEditInfo,"members_can_add_members":membersCanAddMembers})
	broadcastConversationUpdate(groupID,"group_settings_update")
	c.JSON(http.StatusOK,gin.H{"id":groupID,"name":name,"description":description,"privacy":input.Privacy,"announcement_only":announcementOnly,"join_approval_required":joinApprovalRequired,"members_can_edit_info":membersCanEditInfo,"members_can_add_members":membersCanAddMembers,"admin":role=="admin","can_edit_info":groupCanEditInfo(role,membersCanEditInfo),"can_add_members":groupCanAddMembers(role,membersCanAddMembers)})
}

func addGroupMembers(c *gin.Context) { mutateGroupMembers(c,true) }
func removeGroupMember(c *gin.Context) { mutateGroupMembers(c,false) }
func mutateGroupMembers(c *gin.Context,add bool){
	groupID,userID:=c.Param("id"),c.GetString("user_id")
	ctx:=c.Request.Context();tx,err:=db.Begin(ctx);if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"group members could not be updated"});return};defer tx.Rollback(ctx)
	access,accessErr:=loadGroupManagementAccess(ctx,tx,groupID,userID)
	if accessErr!=nil||(add&&!groupCanAddMembers(access.role,access.membersCanAddMembers))||(!add&&access.role!="admin"){c.JSON(http.StatusForbidden,gin.H{"error":"admin access required"});return}
	actorName,err:=groupActivityUserName(ctx,tx,groupID,userID);if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"group activity could not be saved"});return}
	activities:=make([]groupActivityMessage,0);removedUserID:=""
	if add{
		var input struct{MemberIDs []string `json:"member_ids" binding:"required,min=1"`}
		if c.ShouldBindJSON(&input)!=nil{c.JSON(http.StatusBadRequest,gin.H{"error":"member_ids required"});return}
		seen:=make(map[string]bool)
		for _,id:=range input.MemberIDs{
			if id==userID||seen[id]{continue};seen[id]=true
			var targetName string
			if tx.QueryRow(ctx,`SELECT COALESCE(NULLIF(full_name,''),NULLIF(username,''),'GroopX member') FROM users WHERE id=$1 AND account_status='active'`,id).Scan(&targetName)!=nil{c.JSON(http.StatusBadRequest,gin.H{"error":"one or more members are invalid"});return}
			result,execErr:=tx.Exec(ctx,`INSERT INTO conversation_members(conversation_id,user_id,role) SELECT $1,$2,'member' WHERE EXISTS(SELECT 1 FROM conversations WHERE id=$1 AND kind IN ('group','community') AND deleted_at IS NULL) ON CONFLICT DO NOTHING`,groupID,id)
			if execErr!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"group members could not be updated"});return}
			if _,execErr=tx.Exec(ctx,`UPDATE group_join_requests SET status='approved',reviewed_by=$3,reviewed_at=NOW(),updated_at=NOW() WHERE conversation_id=$1 AND user_id=$2 AND status='pending'`,groupID,id,userID);execErr!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"group members could not be updated"});return}
			if _,execErr=tx.Exec(ctx,`UPDATE notifications notification SET read_at=COALESCE(read_at,NOW()) WHERE type='group_join_request' AND EXISTS(SELECT 1 FROM group_join_requests request WHERE request.conversation_id=$1 AND request.user_id=$2 AND notification.data->>'request_id'=request.id::text)`,groupID,id);execErr!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"group members could not be updated"});return}
			if result.RowsAffected()>0{activity,activityErr:=recordGroupActivity(ctx,tx,groupID,"member_added",userID,id,groupActivityText("member_added",actorName,targetName,""));if activityErr!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"group activity could not be saved"});return};activities=append(activities,activity)}
		}
	}else{
		if c.Param("userId")==userID{c.JSON(http.StatusBadRequest,gin.H{"error":"use leave group to remove yourself"});return}
		removedUserID=c.Param("userId");var role,targetName string
		if tx.QueryRow(ctx,`SELECT member.role,COALESCE(NULLIF(member.group_display_name,''),NULLIF(target.full_name,''),NULLIF(target.username,''),'GroopX member') FROM conversation_members member JOIN users target ON target.id=member.user_id WHERE member.conversation_id=$1 AND member.user_id=$2 FOR UPDATE OF member`,groupID,removedUserID).Scan(&role,&targetName)!=nil{c.JSON(http.StatusNotFound,gin.H{"error":"member not found"});return}
		var adminCount int;if err=tx.QueryRow(ctx,`SELECT COUNT(*)::int FROM conversation_members WHERE conversation_id=$1 AND role='admin'`,groupID).Scan(&adminCount);err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"group members could not be updated"});return}
		if role=="admin"&&adminCount<=1{c.JSON(http.StatusConflict,gin.H{"error":"group must have at least one admin"});return}
		result,execErr:=tx.Exec(ctx,`DELETE FROM conversation_members WHERE conversation_id=$1 AND user_id=$2`,groupID,removedUserID);if execErr!=nil||result.RowsAffected()==0{c.JSON(http.StatusInternalServerError,gin.H{"error":"group member could not be removed"});return}
		activity,activityErr:=recordGroupActivity(ctx,tx,groupID,"member_removed",userID,removedUserID,groupActivityText("member_removed",actorName,targetName,""));if activityErr!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"group activity could not be saved"});return};activities=append(activities,activity)
	}
	if tx.Commit(ctx)!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"group members could not be updated"});return}
	if removedUserID!=""{disconnectRoomUser(groupID,removedUserID);broadcast("user:"+removedUserID,"",gin.H{"type":"conversation_update","conversation_id":groupID,"reason":"group_member_removed"})}
	for index:=range activities{publishGroupActivity(&activities[index])}
	broadcast(groupID,userID,gin.H{"type":"group_member_update","conversation_id":groupID})
	broadcastConversationUpdate(groupID,"group_member_update")
	c.Status(http.StatusNoContent)
}

func updateGroupMemberRole(c *gin.Context) {
	groupID, actorID, targetID := c.Param("id"), c.GetString("user_id"), c.Param("userId")
	var input struct {
		Role string `json:"role" binding:"required,oneof=admin member"`
	}
	if c.ShouldBindJSON(&input) != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "role must be admin or member"})
		return
	}

	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "member role could not be updated"})
		return
	}
	defer tx.Rollback(ctx)

	var actorRole, conversationKind string
	err = tx.QueryRow(ctx, `SELECT actor_member.role,conversation.kind::text FROM conversations conversation
		JOIN conversation_members actor_member ON actor_member.conversation_id=conversation.id AND actor_member.user_id=$2
		WHERE conversation.id=$1 AND conversation.kind IN ('group','community') AND conversation.deleted_at IS NULL
		FOR UPDATE OF conversation,actor_member`, groupID, actorID).Scan(&actorRole, &conversationKind)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusForbidden, gin.H{"error": "admin access required"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "member role could not be updated"})
		return
	}
	if actorRole != "admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "admin access required"})
		return
	}

	var currentRole, targetName string
	err = tx.QueryRow(ctx, `SELECT member.role,COALESCE(NULLIF(member.group_display_name,''),NULLIF(target.full_name,''),NULLIF(target.username,''),'GroopX member')
		FROM conversation_members member JOIN users target ON target.id=member.user_id
		WHERE member.conversation_id=$1 AND member.user_id=$2 FOR UPDATE OF member`, groupID, targetID).Scan(&currentRole, &targetName)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "member not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "member role could not be updated"})
		return
	}
	if currentRole == input.Role {
		if tx.Commit(ctx) != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "member role could not be updated"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"message": "member role unchanged", "role": input.Role})
		return
	}

	var adminCount int
	if err = tx.QueryRow(ctx, `SELECT COUNT(*)::int FROM conversation_members WHERE conversation_id=$1 AND role='admin'`, groupID).Scan(&adminCount); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "member role could not be updated"})
		return
	}
	if currentRole == "admin" && input.Role == "member" && adminCount <= 1 {
		c.JSON(http.StatusConflict, gin.H{"error": "promote another admin first"})
		return
	}
	if _, err = tx.Exec(ctx, `UPDATE conversation_members SET role=$3 WHERE conversation_id=$1 AND user_id=$2`, groupID, targetID, input.Role); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "member role could not be updated"})
		return
	}
	actorName, err := groupActivityUserName(ctx, tx, groupID, actorID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "group activity could not be saved"})
		return
	}
	event := "admin_revoked"
	if input.Role == "admin" {
		event = "admin_granted"
	}
	if conversationKind == "community" {
		event = "community_admin_revoked"
		if input.Role == "admin" {
			event = "community_admin_granted"
		}
	}
	activity, err := recordGroupActivity(ctx, tx, groupID, event, actorID, targetID, groupActivityText(event, actorName, targetName, ""))
	if err != nil || tx.Commit(ctx) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "member role could not be updated"})
		return
	}
	publishGroupActivity(&activity)
	broadcast(groupID, actorID, gin.H{"type": "group_settings_update", "conversation_id": groupID})
	broadcastConversationUpdate(groupID, conversationKind+"_member_role_update")
	c.JSON(http.StatusOK, gin.H{"message": "member role updated", "role": input.Role})
}

func joinGroupInvite(c *gin.Context){
	userID,hash:=c.GetString("user_id"),tokenHash(c.Param("token"));ctx:=c.Request.Context();tx,err:=db.Begin(ctx)
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"invite unavailable"});return};defer tx.Rollback(ctx)
	var inviteID,groupID,kind,groupName string;var joinApprovalRequired bool
	err=tx.QueryRow(ctx,`SELECT gi.id::text,gi.conversation_id::text,c.kind::text,COALESCE(c.title,'Group'),COALESCE(c.join_approval_required,FALSE)
		FROM group_invites gi JOIN conversations c ON c.id=gi.conversation_id
		WHERE gi.token_hash=$1 AND gi.revoked_at IS NULL AND gi.expires_at>NOW() AND c.deleted_at IS NULL
		AND (gi.use_count<gi.max_uses OR EXISTS(SELECT 1 FROM group_join_requests request WHERE request.invite_id=gi.id AND request.user_id=$2 AND request.status='pending'))
		FOR UPDATE OF gi,c`,hash,userID).Scan(&inviteID,&groupID,&kind,&groupName,&joinApprovalRequired)
	if err!=nil{c.JSON(http.StatusNotFound,gin.H{"error":"invite is invalid or expired"});return}
	var alreadyMember,pendingRequest bool
	if err=tx.QueryRow(ctx,`SELECT EXISTS(SELECT 1 FROM conversation_members WHERE conversation_id=$1 AND user_id=$2),EXISTS(SELECT 1 FROM group_join_requests WHERE conversation_id=$1 AND user_id=$2 AND status='pending')`,groupID,userID).Scan(&alreadyMember,&pendingRequest);err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"invite could not be checked"});return}
	if alreadyMember{
		_,_=tx.Exec(ctx,`UPDATE group_join_requests SET status='approved',reviewed_at=COALESCE(reviewed_at,NOW()),updated_at=NOW() WHERE conversation_id=$1 AND user_id=$2 AND status='pending'`,groupID,userID)
		_,_=tx.Exec(ctx,`UPDATE notifications notification SET read_at=COALESCE(read_at,NOW()) WHERE type='group_join_request' AND EXISTS(SELECT 1 FROM group_join_requests request WHERE request.conversation_id=$1 AND request.user_id=$2 AND notification.data->>'request_id'=request.id::text)`,groupID,userID)
		if tx.Commit(ctx)!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"group membership could not be checked"});return}
		c.JSON(http.StatusOK,gin.H{"message":"already a group member","status":"joined","group_id":groupID,"kind":kind});return
	}
	if groupJoinNeedsApproval(kind,joinApprovalRequired,alreadyMember){
		request,requestErr:=queueGroupJoinRequest(ctx,tx,inviteID,groupID,userID,groupName)
		if requestErr!=nil||tx.Commit(ctx)!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"join request could not be sent"});return}
		if request.created{go sendPushToUsers(request.adminIDs,"group_join_request","New group join request","Someone requested to join "+groupName,map[string]any{"group_id":groupID,"request_id":request.id})}
		c.JSON(http.StatusAccepted,gin.H{"message":"Your request was sent to the group admins.","status":"pending","request_id":request.id,"group_id":groupID,"kind":kind});return
	}
	result,err:=tx.Exec(ctx,`INSERT INTO conversation_members(conversation_id,user_id,role) VALUES($1,$2,'member') ON CONFLICT DO NOTHING`,groupID,userID);joined:=err==nil&&result.RowsAffected()>0
	if err==nil&&result.RowsAffected()>0&&!pendingRequest{_,err=tx.Exec(ctx,`UPDATE group_invites SET use_count=use_count+1 WHERE id=$1`,inviteID)}
	if err==nil&&pendingRequest{_,err=tx.Exec(ctx,`UPDATE group_join_requests SET status='approved',reviewed_at=NOW(),updated_at=NOW() WHERE conversation_id=$1 AND user_id=$2 AND status='pending'`,groupID,userID)}
	if err==nil&&pendingRequest{_,err=tx.Exec(ctx,`UPDATE notifications notification SET read_at=COALESCE(read_at,NOW()) WHERE type='group_join_request' AND EXISTS(SELECT 1 FROM group_join_requests request WHERE request.conversation_id=$1 AND request.user_id=$2 AND notification.data->>'request_id'=request.id::text)`,groupID,userID)}
	var activity *groupActivityMessage
	if err==nil&&joined{actorName,nameErr:=groupActivityUserName(ctx,tx,groupID,userID);if nameErr!=nil{err=nameErr}else{saved,activityErr:=recordGroupActivity(ctx,tx,groupID,"member_joined",userID,"",groupActivityText("member_joined",actorName,"",""));if activityErr!=nil{err=activityErr}else{activity=&saved}}}
	if err!=nil||tx.Commit(ctx)!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"group could not be joined"});return}
	publishGroupActivity(activity);if joined{broadcast(groupID,userID,gin.H{"type":"group_member_update","conversation_id":groupID,"user_id":userID});broadcastConversationUpdate(groupID,"group_member_joined")}
	c.JSON(http.StatusOK,gin.H{"message":"invite joined","status":"joined","group_id":groupID,"kind":kind})
}

func leaveGroup(c *gin.Context) {
	groupID, userID := c.Param("id"), c.GetString("user_id")
	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not leave conversation"})
		return
	}
	defer tx.Rollback(ctx)

	var role, name, conversationKind string
	err = tx.QueryRow(ctx, `SELECT member.role,
		COALESCE(NULLIF(member.group_display_name,''),NULLIF(member_user.full_name,''),NULLIF(member_user.username,''),'GroopX member'),
		conversation.kind::text
		FROM conversations conversation
		JOIN conversation_members member ON member.conversation_id=conversation.id AND member.user_id=$2
		JOIN users member_user ON member_user.id=member.user_id
		WHERE conversation.id=$1 AND conversation.kind IN ('group','community') AND conversation.deleted_at IS NULL
		FOR UPDATE OF conversation,member`, groupID, userID).Scan(&role, &name, &conversationKind)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "membership not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not leave conversation"})
		return
	}
	var adminCount, memberCount int
	if err = tx.QueryRow(ctx, `SELECT COUNT(*) FILTER (WHERE role='admin')::int,COUNT(*)::int FROM conversation_members WHERE conversation_id=$1`, groupID).Scan(&adminCount, &memberCount); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not leave conversation"})
		return
	}
	if role == "admin" && adminCount <= 1 && memberCount > 1 {
		c.JSON(http.StatusConflict, gin.H{"error": "promote another admin before leaving"})
		return
	}
	result, err := tx.Exec(ctx, `DELETE FROM conversation_members WHERE conversation_id=$1 AND user_id=$2`, groupID, userID)
	if err != nil || result.RowsAffected() == 0 {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not leave conversation"})
		return
	}
	event := "member_left"
	if conversationKind == "community" {
		event = "community_member_left"
	}
	activity, err := recordGroupActivity(ctx, tx, groupID, event, userID, "", groupActivityText(event, name, "", ""))
	if err != nil || tx.Commit(ctx) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not leave conversation"})
		return
	}
	disconnectRoomUser(groupID, userID)
	broadcast("user:"+userID, "", gin.H{"type": "conversation_update", "conversation_id": groupID, "reason": conversationKind + "_member_left"})
	publishGroupActivity(&activity)
	c.Status(http.StatusNoContent)
}

func isGroupAdmin(groupID,userID string)bool{var admin bool;_ = db.QueryRow(context.Background(),`SELECT EXISTS(SELECT 1 FROM conversation_members cm JOIN conversations c ON c.id=cm.conversation_id WHERE cm.conversation_id=$1 AND cm.user_id=$2 AND cm.role='admin' AND c.kind IN ('group','community') AND c.deleted_at IS NULL)`,groupID,userID).Scan(&admin);return admin}
func groupAdminCount(groupID string)int{var count int;_ = db.QueryRow(context.Background(),`SELECT COUNT(*) FROM conversation_members WHERE conversation_id=$1 AND role='admin'`,groupID).Scan(&count);return count}

package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
)

func searchUsers(c *gin.Context) {
	query := strings.TrimSpace(c.Query("q"))
	if len(query) < 2 { c.JSON(http.StatusOK, gin.H{"items": []gin.H{}}); return }
	rows, err := db.Query(c.Request.Context(), `SELECT id::text, COALESCE(full_name,username,'GroopX User'), COALESCE(username,''), avatar_url
		FROM users WHERE id<>$1 AND NOT EXISTS(SELECT 1 FROM user_blocks b WHERE (b.blocker_id=$1 AND b.blocked_id=users.id) OR (b.blocker_id=users.id AND b.blocked_id=$1))
		AND (username ILIKE $2 OR full_name ILIKE $2 OR phone ILIKE $2) ORDER BY full_name NULLS LAST LIMIT 20`, c.GetString("user_id"), "%"+query+"%")
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"search unavailable"}); return }
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() { var id,name,username string; var avatar *string; if rows.Scan(&id,&name,&username,&avatar)==nil { items=append(items,gin.H{"id":id,"name":name,"username":username,"avatar_url":avatar}) } }
	c.JSON(http.StatusOK, gin.H{"items":items})
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
	var input struct { DisplayName string `json:"display_name" binding:"required,max=120"`; Phone string `json:"phone" binding:"omitempty,max=20"`; Username string `json:"username" binding:"omitempty,max=40"`; Notes string `json:"notes" binding:"omitempty,max=100"` }
	if c.ShouldBindJSON(&input)!=nil || (strings.TrimSpace(input.Phone)=="" && strings.TrimSpace(input.Username)=="") { c.JSON(http.StatusBadRequest,gin.H{"error":"name and phone or username are required"}); return }
	ctx:=c.Request.Context(); tx,err:=db.Begin(ctx); if err!=nil { c.JSON(http.StatusInternalServerError,gin.H{"error":"contact could not be saved"}); return }; defer tx.Rollback(ctx)
	var contactUserID string
	err=tx.QueryRow(ctx,`SELECT id::text FROM users WHERE ($1<>'' AND phone=$1) OR ($2<>'' AND LOWER(username)=LOWER($2)) LIMIT 1`,strings.TrimSpace(input.Phone),strings.TrimPrefix(strings.TrimSpace(input.Username),"@")).Scan(&contactUserID)
	if errors.Is(err,pgx.ErrNoRows) { c.JSON(http.StatusNotFound,gin.H{"error":"GroopX user not found"}); return }
	if err!=nil || contactUserID==ownerID { c.JSON(http.StatusBadRequest,gin.H{"error":"invalid contact"}); return }
	if usersBlocked(ownerID,contactUserID) { c.JSON(http.StatusForbidden,gin.H{"error":"contact cannot be added because communication is blocked"}); return }
	_,err=tx.Exec(ctx,`INSERT INTO contacts(owner_id,contact_user_id,display_name,phone,username,notes) VALUES($1,$2,$3,NULLIF($4,''),NULLIF($5,''),NULLIF($6,''))
		ON CONFLICT(owner_id,display_name) DO UPDATE SET contact_user_id=EXCLUDED.contact_user_id,phone=EXCLUDED.phone,username=EXCLUDED.username,notes=EXCLUDED.notes`,ownerID,contactUserID,strings.TrimSpace(input.DisplayName),strings.TrimSpace(input.Phone),strings.TrimPrefix(strings.TrimSpace(input.Username),"@"),strings.TrimSpace(input.Notes))
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
	var input struct { Name string `json:"name" binding:"required,max=50"`; Description string `json:"description" binding:"omitempty,max=200"`; Privacy string `json:"privacy" binding:"required,oneof=private public"`; MemberIDs []string `json:"member_ids" binding:"required,min=1"` }
	if c.ShouldBindJSON(&input)!=nil { c.JSON(http.StatusBadRequest,gin.H{"error":"invalid group"}); return }
	ctx:=c.Request.Context(); tx,err:=db.Begin(ctx); if err!=nil { c.JSON(http.StatusInternalServerError,gin.H{"error":"group could not be created"}); return }; defer tx.Rollback(ctx)
	var id string; err=tx.QueryRow(ctx,`INSERT INTO conversations(kind,title,description,privacy,created_by) VALUES('group',$1,$2,$3,$4) RETURNING id::text`,strings.TrimSpace(input.Name),strings.TrimSpace(input.Description),input.Privacy,creatorID).Scan(&id)
	if err!=nil { c.JSON(http.StatusInternalServerError,gin.H{"error":"group could not be created"}); return }
	_,err=tx.Exec(ctx,`INSERT INTO conversation_members(conversation_id,user_id,role) VALUES($1,$2,'admin')`,id,creatorID); if err!=nil { c.JSON(http.StatusInternalServerError,gin.H{"error":"group creator could not be added"}); return }
	for _,memberID:=range input.MemberIDs { if memberID==creatorID {continue}; if _,err=tx.Exec(ctx,`INSERT INTO conversation_members(conversation_id,user_id,role) VALUES($1,$2,'member') ON CONFLICT DO NOTHING`,id,memberID); err!=nil { c.JSON(http.StatusBadRequest,gin.H{"error":"one or more members are invalid"}); return } }
	if tx.Commit(ctx)!=nil { c.JSON(http.StatusInternalServerError,gin.H{"error":"group could not be saved"}); return }
	c.JSON(http.StatusCreated,gin.H{"id":id,"name":input.Name,"privacy":input.Privacy})
}

func getGroup(c *gin.Context) {
	id,userID:=c.Param("id"),c.GetString("user_id"); if !isConversationMember(c,id,userID){c.JSON(http.StatusForbidden,gin.H{"error":"not a group member"});return}
	var name,description,privacy string; err:=db.QueryRow(c.Request.Context(),`SELECT title,COALESCE(description,''),COALESCE(privacy::text,'private') FROM conversations WHERE id=$1 AND kind IN ('group','community') AND deleted_at IS NULL`,id).Scan(&name,&description,&privacy)
	if err!=nil { c.JSON(http.StatusNotFound,gin.H{"error":"group not found"});return }
	rows,err:=db.Query(c.Request.Context(),`SELECT u.id::text,COALESCE(u.full_name,u.phone),COALESCE(u.username,''),cm.role FROM conversation_members cm JOIN users u ON u.id=cm.user_id WHERE cm.conversation_id=$1 ORDER BY (cm.role='admin') DESC,u.full_name`,id)
	if err!=nil { c.JSON(http.StatusInternalServerError,gin.H{"error":"members could not be loaded"});return}; defer rows.Close(); members:=make([]gin.H,0)
	for rows.Next(){var memberID,memberName,username,role string;if rows.Scan(&memberID,&memberName,&username,&role)==nil{members=append(members,gin.H{"id":memberID,"name":memberName,"username":username,"role":role,"mine":memberID==userID})}}
	c.JSON(http.StatusOK,gin.H{"id":id,"name":name,"description":description,"privacy":privacy,"members":members})
}

func updateGroup(c *gin.Context) {
	groupID,userID:=c.Param("id"),c.GetString("user_id")
	if !isGroupAdmin(groupID,userID){c.JSON(http.StatusForbidden,gin.H{"error":"admin access required"});return}
	var input struct{Name string `json:"name" binding:"required,max=50"`;Description string `json:"description" binding:"omitempty,max=200"`;Privacy string `json:"privacy" binding:"required,oneof=private public"`}
	if c.ShouldBindJSON(&input)!=nil||len(strings.TrimSpace(input.Name))<2{c.JSON(http.StatusBadRequest,gin.H{"error":"valid group name and privacy are required"});return}
	command,err:=db.Exec(c.Request.Context(),`UPDATE conversations SET title=$2,description=NULLIF($3,''),privacy=$4 WHERE id=$1 AND kind='group' AND deleted_at IS NULL`,groupID,strings.TrimSpace(input.Name),strings.TrimSpace(input.Description),input.Privacy)
	if err!=nil||command.RowsAffected()==0{c.JSON(http.StatusNotFound,gin.H{"error":"group could not be updated"});return}
	c.JSON(http.StatusOK,gin.H{"id":groupID,"name":strings.TrimSpace(input.Name),"description":strings.TrimSpace(input.Description),"privacy":input.Privacy})
}

func addGroupMembers(c *gin.Context) { mutateGroupMembers(c,true) }
func removeGroupMember(c *gin.Context) { mutateGroupMembers(c,false) }
func mutateGroupMembers(c *gin.Context,add bool){groupID,userID:=c.Param("id"),c.GetString("user_id");if !isGroupAdmin(groupID,userID){c.JSON(http.StatusForbidden,gin.H{"error":"admin access required"});return};if add{var input struct{MemberIDs []string `json:"member_ids" binding:"required,min=1"`};if c.ShouldBindJSON(&input)!=nil{c.JSON(http.StatusBadRequest,gin.H{"error":"member_ids required"});return};for _,id:=range input.MemberIDs{_,_ = db.Exec(c.Request.Context(),`INSERT INTO conversation_members(conversation_id,user_id,role) SELECT $1,$2,'member' WHERE EXISTS(SELECT 1 FROM conversations WHERE id=$1 AND kind IN ('group','community') AND deleted_at IS NULL) ON CONFLICT DO NOTHING`,groupID,id)}}else{if c.Param("userId")==userID{c.JSON(http.StatusBadRequest,gin.H{"error":"use leave group to remove yourself"});return};var role string;if db.QueryRow(c.Request.Context(),`SELECT role FROM conversation_members WHERE conversation_id=$1 AND user_id=$2`,groupID,c.Param("userId")).Scan(&role)!=nil{c.JSON(http.StatusNotFound,gin.H{"error":"member not found"});return};if role=="admin"&&groupAdminCount(groupID)<=1{c.JSON(http.StatusConflict,gin.H{"error":"group must have at least one admin"});return};_,_ = db.Exec(c.Request.Context(),`DELETE FROM conversation_members WHERE conversation_id=$1 AND user_id=$2`,groupID,c.Param("userId"))};c.Status(http.StatusNoContent)}

func updateGroupMemberRole(c *gin.Context){
	groupID,actorID,targetID:=c.Param("id"),c.GetString("user_id"),c.Param("userId")
	if !isGroupAdmin(groupID,actorID){c.JSON(http.StatusForbidden,gin.H{"error":"admin access required"});return}
	var input struct{Role string `json:"role" binding:"required,oneof=admin member"`}
	if c.ShouldBindJSON(&input)!=nil{c.JSON(http.StatusBadRequest,gin.H{"error":"role must be admin or member"});return}
	var currentRole string
	if db.QueryRow(c.Request.Context(),`SELECT role FROM conversation_members WHERE conversation_id=$1 AND user_id=$2`,groupID,targetID).Scan(&currentRole)!=nil{c.JSON(http.StatusNotFound,gin.H{"error":"member not found"});return}
	if currentRole=="admin"&&input.Role=="member"&&groupAdminCount(groupID)<=1{c.JSON(http.StatusConflict,gin.H{"error":"promote another admin first"});return}
	_,err:=db.Exec(c.Request.Context(),`UPDATE conversation_members SET role=$3 WHERE conversation_id=$1 AND user_id=$2`,groupID,targetID,input.Role)
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"member role could not be updated"});return}
	c.JSON(http.StatusOK,gin.H{"message":"member role updated","role":input.Role})
}

func createGroupInvite(c *gin.Context){
	groupID,userID:=c.Param("id"),c.GetString("user_id")
	if !isGroupAdmin(groupID,userID){c.JSON(http.StatusForbidden,gin.H{"error":"admin access required"});return}
	var input struct{ExpiresInHours int `json:"expires_in_hours" binding:"omitempty,gte=1,lte=168"`;MaxUses int `json:"max_uses" binding:"omitempty,gte=1,lte=500"`}
	if c.ShouldBindJSON(&input)!=nil{c.JSON(http.StatusBadRequest,gin.H{"error":"invalid invite settings"});return}
	if input.ExpiresInHours==0{input.ExpiresInHours=24};if input.MaxUses==0{input.MaxUses=50}
	token,hash,err:=newRefreshToken();if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"invite could not be created"});return}
	expiresAt:=time.Now().Add(time.Duration(input.ExpiresInHours)*time.Hour)
	_,err=db.Exec(c.Request.Context(),`INSERT INTO group_invites(conversation_id,token_hash,created_by,expires_at,max_uses) VALUES($1,$2,$3,$4,$5)`,groupID,hash,userID,expiresAt,input.MaxUses)
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"invite could not be saved"});return}
	c.JSON(http.StatusCreated,gin.H{"token":token,"invite_link":"groopx:///join/"+token,"expires_at":expiresAt,"max_uses":input.MaxUses})
}

func joinGroupInvite(c *gin.Context){
	userID,hash:=c.GetString("user_id"),tokenHash(c.Param("token"));ctx:=c.Request.Context();tx,err:=db.Begin(ctx)
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"invite unavailable"});return};defer tx.Rollback(ctx)
	var inviteID,groupID,kind string
	err=tx.QueryRow(ctx,`SELECT gi.id::text,gi.conversation_id::text,c.kind::text FROM group_invites gi JOIN conversations c ON c.id=gi.conversation_id WHERE gi.token_hash=$1 AND gi.revoked_at IS NULL AND gi.expires_at>NOW() AND gi.use_count<gi.max_uses AND c.deleted_at IS NULL FOR UPDATE OF gi`,hash).Scan(&inviteID,&groupID,&kind)
	if err!=nil{c.JSON(http.StatusNotFound,gin.H{"error":"invite is invalid or expired"});return}
	result,err:=tx.Exec(ctx,`INSERT INTO conversation_members(conversation_id,user_id,role) VALUES($1,$2,'member') ON CONFLICT DO NOTHING`,groupID,userID)
	if err==nil&&result.RowsAffected()>0{_,err=tx.Exec(ctx,`UPDATE group_invites SET use_count=use_count+1 WHERE id=$1`,inviteID)}
	if err!=nil||tx.Commit(ctx)!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"group could not be joined"});return}
	c.JSON(http.StatusOK,gin.H{"message":"invite joined","group_id":groupID,"kind":kind})
}

func leaveGroup(c *gin.Context){groupID,userID:=c.Param("id"),c.GetString("user_id");if isGroupAdmin(groupID,userID)&&groupAdminCount(groupID)<=1{var members int;_ = db.QueryRow(c.Request.Context(),`SELECT COUNT(*) FROM conversation_members WHERE conversation_id=$1`,groupID).Scan(&members);if members>1{c.JSON(http.StatusConflict,gin.H{"error":"promote another admin before leaving"});return}};_,err:=db.Exec(c.Request.Context(),`DELETE FROM conversation_members WHERE conversation_id=$1 AND user_id=$2`,groupID,userID);if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"could not leave group"});return};c.Status(http.StatusNoContent)}

func isGroupAdmin(groupID,userID string)bool{var admin bool;_ = db.QueryRow(context.Background(),`SELECT EXISTS(SELECT 1 FROM conversation_members cm JOIN conversations c ON c.id=cm.conversation_id WHERE cm.conversation_id=$1 AND cm.user_id=$2 AND cm.role='admin' AND c.kind IN ('group','community') AND c.deleted_at IS NULL)`,groupID,userID).Scan(&admin);return admin}
func groupAdminCount(groupID string)int{var count int;_ = db.QueryRow(context.Background(),`SELECT COUNT(*) FROM conversation_members WHERE conversation_id=$1 AND role='admin'`,groupID).Scan(&count);return count}

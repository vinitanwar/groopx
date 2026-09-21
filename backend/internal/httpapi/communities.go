package httpapi

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

func listCommunities(c *gin.Context) {
	userID := c.GetString("user_id")
	rows, err := db.Query(c.Request.Context(), `SELECT c.id::text,COALESCE(c.title,''),COALESCE(c.description,''),cm.role,
		(SELECT COUNT(*) FROM community_groups cg WHERE cg.community_id=c.id),
		(SELECT COUNT(*) FROM conversation_members members WHERE members.conversation_id=c.id)
		FROM conversations c JOIN conversation_members cm ON cm.conversation_id=c.id AND cm.user_id=$1
		WHERE c.kind='community' AND c.deleted_at IS NULL ORDER BY c.updated_at DESC`, userID)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"communities could not be loaded"}); return }
	defer rows.Close(); items:=make([]gin.H,0)
	for rows.Next(){var id,name,description,role string;var groupCount,memberCount int;if rows.Scan(&id,&name,&description,&role,&groupCount,&memberCount)==nil{items=append(items,gin.H{"id":id,"name":name,"description":description,"role":role,"group_count":groupCount,"member_count":memberCount})}}
	c.JSON(http.StatusOK,gin.H{"items":items})
}

func listManageableGroups(c *gin.Context) {
	rows,err:=db.Query(c.Request.Context(),`SELECT c.id::text,COALESCE(c.title,''),(SELECT COUNT(*) FROM conversation_members WHERE conversation_id=c.id) FROM conversations c JOIN conversation_members cm ON cm.conversation_id=c.id AND cm.user_id=$1 AND cm.role='admin' WHERE c.kind='group' AND c.deleted_at IS NULL ORDER BY c.title`,c.GetString("user_id"))
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"groups could not be loaded"});return};defer rows.Close();items:=make([]gin.H,0)
	for rows.Next(){var id,name string;var members int;if rows.Scan(&id,&name,&members)==nil{items=append(items,gin.H{"id":id,"name":name,"member_count":members})}}
	c.JSON(http.StatusOK,gin.H{"items":items})
}

func createCommunity(c *gin.Context) {
	userID:=c.GetString("user_id")
	var input struct{Name string `json:"name" binding:"required,min=2,max=80"`;Description string `json:"description" binding:"omitempty,max=200"`}
	if c.ShouldBindJSON(&input)!=nil{c.JSON(http.StatusBadRequest,gin.H{"error":"invalid community"});return}
	ctx:=c.Request.Context();tx,err:=db.Begin(ctx);if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"community could not be created"});return};defer tx.Rollback(ctx)
	var id string;err=tx.QueryRow(ctx,`INSERT INTO conversations(kind,title,description,privacy,created_by) VALUES('community',$1,$2,'private',$3) RETURNING id::text`,strings.TrimSpace(input.Name),strings.TrimSpace(input.Description),userID).Scan(&id)
	if err==nil{_,err=tx.Exec(ctx,`INSERT INTO conversation_members(conversation_id,user_id,role) VALUES($1,$2,'admin')`,id,userID)}
	if err!=nil||tx.Commit(ctx)!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"community could not be saved"});return}
	c.JSON(http.StatusCreated,gin.H{"id":id,"name":strings.TrimSpace(input.Name)})
}

func getCommunity(c *gin.Context) {
	id,userID:=c.Param("id"),c.GetString("user_id")
	if !isConversationMember(c,id,userID){c.JSON(http.StatusForbidden,gin.H{"error":"not a community member"});return}
	var name,description,role string
	err:=db.QueryRow(c.Request.Context(),`SELECT COALESCE(c.title,''),COALESCE(c.description,''),cm.role FROM conversations c JOIN conversation_members cm ON cm.conversation_id=c.id AND cm.user_id=$2 WHERE c.id=$1 AND c.kind='community' AND c.deleted_at IS NULL`,id,userID).Scan(&name,&description,&role)
	if err!=nil{c.JSON(http.StatusNotFound,gin.H{"error":"community not found"});return}
	rows,err:=db.Query(c.Request.Context(),`SELECT g.id::text,COALESCE(g.title,''),(SELECT COUNT(*) FROM conversation_members WHERE conversation_id=g.id) FROM community_groups cg JOIN conversations g ON g.id=cg.group_id WHERE cg.community_id=$1 AND g.deleted_at IS NULL ORDER BY g.title`,id)
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"community groups could not be loaded"});return};defer rows.Close();groups:=make([]gin.H,0)
	for rows.Next(){var groupID,title string;var memberCount int;if rows.Scan(&groupID,&title,&memberCount)==nil{groups=append(groups,gin.H{"id":groupID,"name":title,"member_count":memberCount})}}
	c.JSON(http.StatusOK,gin.H{"id":id,"name":name,"description":description,"role":role,"groups":groups})
}

func addCommunityGroup(c *gin.Context) {
	communityID,userID:=c.Param("id"),c.GetString("user_id")
	if !isGroupAdmin(communityID,userID){c.JSON(http.StatusForbidden,gin.H{"error":"community admin access required"});return}
	var input struct{GroupID string `json:"group_id" binding:"required,uuid"`}
	if c.ShouldBindJSON(&input)!=nil||!isGroupAdmin(input.GroupID,userID){c.JSON(http.StatusForbidden,gin.H{"error":"you must be an admin of both the community and group"});return}
	result,err:=db.Exec(c.Request.Context(),`INSERT INTO community_groups(community_id,group_id,added_by) SELECT $1,$2,$3 WHERE EXISTS(SELECT 1 FROM conversations WHERE id=$1 AND kind='community') AND EXISTS(SELECT 1 FROM conversations WHERE id=$2 AND kind='group') ON CONFLICT DO NOTHING`,communityID,input.GroupID,userID)
	if err!=nil||result.RowsAffected()==0{c.JSON(http.StatusConflict,gin.H{"error":"group could not be added"});return}
	c.Status(http.StatusNoContent)
}

func removeCommunityGroup(c *gin.Context) {
	communityID,userID:=c.Param("id"),c.GetString("user_id")
	if !isGroupAdmin(communityID,userID){c.JSON(http.StatusForbidden,gin.H{"error":"community admin access required"});return}
	_,err:=db.Exec(c.Request.Context(),`DELETE FROM community_groups WHERE community_id=$1 AND group_id=$2`,communityID,c.Param("groupId"))
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"group could not be removed"});return};c.Status(http.StatusNoContent)
}

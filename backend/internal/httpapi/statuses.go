package httpapi

import (
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

func createStatus(c *gin.Context) {
	userID:=c.GetString("user_id")
	var input struct{ ObjectKey string `json:"object_key" binding:"required,max=500"`; FileName string `json:"file_name" binding:"required,max=180"`; ContentType string `json:"content_type" binding:"required,max=120"`; Size int64 `json:"size" binding:"required,gt=0,lte=209715200"`; Caption string `json:"caption" binding:"max=500"` }
	if c.ShouldBindJSON(&input)!=nil || !strings.HasPrefix(input.ObjectKey,"uploads/"+userID+"/"){c.JSON(http.StatusBadRequest,gin.H{"error":"invalid status media"});return}
	kind:="";if strings.HasPrefix(input.ContentType,"image/"){kind="image"}else if strings.HasPrefix(input.ContentType,"video/"){kind="video"}
	if kind==""||cfg.S3PublicBaseURL==""{c.JSON(http.StatusBadRequest,gin.H{"error":"status must be an image or video"});return}
	publicURL:=strings.TrimRight(cfg.S3PublicBaseURL,"/")+"/"+escapeObjectKey(input.ObjectKey)
	ctx:=c.Request.Context();tx,err:=db.Begin(ctx);if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"status could not be saved"});return};defer tx.Rollback(ctx)
	var mediaID,statusID string;var createdAt,expiresAt time.Time
	err=tx.QueryRow(ctx,`INSERT INTO media_objects(owner_id,object_key,file_name,content_type,size_bytes) VALUES($1,$2,$3,$4,$5) RETURNING id::text`,userID,input.ObjectKey,input.FileName,input.ContentType,input.Size).Scan(&mediaID)
	if err==nil{err=tx.QueryRow(ctx,`INSERT INTO statuses(user_id,media_id,media_url,media_type,caption) VALUES($1,$2,$3,$4,NULLIF($5,'')) RETURNING id::text,created_at,expires_at`,userID,mediaID,publicURL,kind,input.Caption).Scan(&statusID,&createdAt,&expiresAt)}
	if err!=nil||tx.Commit(ctx)!=nil{c.JSON(http.StatusConflict,gin.H{"error":"status could not be saved"});return}
	c.JSON(http.StatusCreated,gin.H{"id":statusID,"media_url":publicURL,"media_type":kind,"caption":input.Caption,"created_at":createdAt,"expires_at":expiresAt,"mine":true,"viewed":true})
}

func listStatuses(c *gin.Context) {
	userID:=c.GetString("user_id")
	rows,err:=db.Query(c.Request.Context(),`SELECT s.id::text,s.user_id::text,COALESCE(u.full_name,u.username,'GroopX user'),COALESCE(u.avatar_url,''),s.media_url,s.media_type,s.caption,s.created_at,s.expires_at,(s.user_id=$1),EXISTS(SELECT 1 FROM status_views v WHERE v.status_id=s.id AND v.user_id=$1),(SELECT COUNT(*) FROM status_views v WHERE v.status_id=s.id)
		FROM statuses s JOIN users u ON u.id=s.user_id WHERE s.expires_at>NOW() AND (s.user_id=$1 OR EXISTS(SELECT 1 FROM contacts c WHERE c.owner_id=$1 AND c.contact_user_id=s.user_id)) AND NOT EXISTS(SELECT 1 FROM user_blocks b WHERE (b.blocker_id=$1 AND b.blocked_id=s.user_id) OR (b.blocker_id=s.user_id AND b.blocked_id=$1)) ORDER BY (s.user_id=$1) DESC,s.created_at DESC`,userID)
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"statuses could not be loaded"});return};defer rows.Close()
	items:=make([]gin.H,0);for rows.Next(){var id,ownerID,name,avatar,url,kind string;var caption *string;var createdAt,expiresAt time.Time;var mine,viewed bool;var views int;if rows.Scan(&id,&ownerID,&name,&avatar,&url,&kind,&caption,&createdAt,&expiresAt,&mine,&viewed,&views)==nil{items=append(items,gin.H{"id":id,"user_id":ownerID,"user_name":name,"avatar_url":avatar,"media_url":url,"media_type":kind,"caption":caption,"created_at":createdAt,"expires_at":expiresAt,"mine":mine,"viewed":viewed,"view_count":views})}}
	c.JSON(http.StatusOK,gin.H{"items":items})
}

func viewStatus(c *gin.Context){userID:=c.GetString("user_id");_,err:=db.Exec(c.Request.Context(),`INSERT INTO status_views(status_id,user_id) SELECT s.id,$2 FROM statuses s WHERE s.id=$1 AND s.expires_at>NOW() AND (s.user_id=$2 OR EXISTS(SELECT 1 FROM contacts c WHERE c.owner_id=$2 AND c.contact_user_id=s.user_id)) ON CONFLICT DO NOTHING`,c.Param("id"),userID);if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"status view could not be saved"});return};c.Status(http.StatusNoContent)}

func deleteStatus(c *gin.Context){result,err:=db.Exec(c.Request.Context(),`DELETE FROM statuses WHERE id=$1 AND user_id=$2`,c.Param("id"),c.GetString("user_id"));if err!=nil||result.RowsAffected()==0{c.JSON(http.StatusNotFound,gin.H{"error":"status not found"});return};c.Status(http.StatusNoContent)}

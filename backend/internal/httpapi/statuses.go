package httpapi

import (
	"crypto/rand"
	"encoding/hex"
	"io"
	"net/http"
	"path"
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

func uploadStatus(c *gin.Context) {
	c.Request.Body=http.MaxBytesReader(c.Writer,c.Request.Body,27*1024*1024)
	fileHeader,err:=c.FormFile("file")
	if err!=nil||fileHeader.Size<=0||fileHeader.Size>25*1024*1024{c.JSON(http.StatusBadRequest,gin.H{"error":"Without external storage, status must be smaller than 25 MB"});return}
	file,err:=fileHeader.Open();if err!=nil{c.JSON(http.StatusBadRequest,gin.H{"error":"status media could not be read"});return};defer file.Close()
	data,err:=io.ReadAll(io.LimitReader(file,25*1024*1024+1));if err!=nil||len(data)==0||len(data)>25*1024*1024{c.JSON(http.StatusBadRequest,gin.H{"error":"Without external storage, status must be smaller than 25 MB"});return}
	fileName:=unsafeFileName.ReplaceAllString(path.Base(fileHeader.Filename),"_");if fileName==""{fileName="status"}
	contentType:=strings.TrimSpace(fileHeader.Header.Get("Content-Type"));if contentType==""||contentType=="application/octet-stream"{contentType=http.DetectContentType(data)}
	kind:="";if strings.HasPrefix(contentType,"image/"){kind="image"}else if strings.HasPrefix(contentType,"video/"){kind="video"}
	if kind==""{c.JSON(http.StatusBadRequest,gin.H{"error":"status must be an image or video"});return}
	caption:=strings.TrimSpace(c.PostForm("caption"));if len([]rune(caption))>500{c.JSON(http.StatusBadRequest,gin.H{"error":"caption is too long"});return}
	random:=make([]byte,16);if _,err=rand.Read(random);err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"status could not be saved"});return}
	objectKey:="database/statuses/"+hex.EncodeToString(random)+"-"+fileName
	ctx:=c.Request.Context();tx,err:=db.Begin(ctx);if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"status could not be saved"});return};defer tx.Rollback(ctx)
	userID:=c.GetString("user_id");var mediaID,statusID string;var createdAt,expiresAt time.Time
	err=tx.QueryRow(ctx,`INSERT INTO media_objects(owner_id,object_key,file_name,content_type,size_bytes) VALUES($1,$2,$3,$4,$5) RETURNING id::text`,userID,objectKey,fileName,contentType,len(data)).Scan(&mediaID)
	if err==nil{_,err=tx.Exec(ctx,`INSERT INTO media_blobs(media_id,file_data) VALUES($1,$2)`,mediaID,data)}
	scheme:=c.GetHeader("X-Forwarded-Proto");if scheme==""{scheme="http";if c.Request.TLS!=nil{scheme="https"}}
	publicURL:=scheme+"://"+c.Request.Host+"/api/v1/media/files/"+mediaID
	if err==nil{err=tx.QueryRow(ctx,`INSERT INTO statuses(user_id,media_id,media_url,media_type,caption) VALUES($1,$2,$3,$4,NULLIF($5,'')) RETURNING id::text,created_at,expires_at`,userID,mediaID,publicURL,kind,caption).Scan(&statusID,&createdAt,&expiresAt)}
	if err!=nil||tx.Commit(ctx)!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"status could not be saved"});return}
	c.JSON(http.StatusCreated,gin.H{"id":statusID,"media_url":publicURL,"media_type":kind,"caption":caption,"created_at":createdAt,"expires_at":expiresAt,"mine":true,"viewed":true})
}

func listStatuses(c *gin.Context) {
	userID:=c.GetString("user_id")
	_,_=db.Exec(c.Request.Context(),`WITH expired AS (DELETE FROM statuses WHERE expires_at<=NOW() RETURNING media_id) DELETE FROM media_objects WHERE id IN (SELECT media_id FROM expired)`)
	rows,err:=db.Query(c.Request.Context(),`SELECT s.id::text,s.user_id::text,COALESCE(u.full_name,u.username,'GroopX user'),COALESCE(u.avatar_url,''),s.media_url,s.media_type,s.caption,s.created_at,s.expires_at,(s.user_id=$1),EXISTS(SELECT 1 FROM status_views v WHERE v.status_id=s.id AND v.user_id=$1),(SELECT COUNT(*) FROM status_views v WHERE v.status_id=s.id)
		FROM statuses s JOIN users u ON u.id=s.user_id WHERE s.expires_at>NOW() AND (s.user_id=$1 OR EXISTS(SELECT 1 FROM contacts c WHERE c.owner_id=$1 AND c.contact_user_id=s.user_id)) AND NOT EXISTS(SELECT 1 FROM user_blocks b WHERE (b.blocker_id=$1 AND b.blocked_id=s.user_id) OR (b.blocker_id=s.user_id AND b.blocked_id=$1)) ORDER BY (s.user_id=$1) DESC,s.created_at DESC`,userID)
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"statuses could not be loaded"});return};defer rows.Close()
	items:=make([]gin.H,0);for rows.Next(){var id,ownerID,name,avatar,url,kind string;var caption *string;var createdAt,expiresAt time.Time;var mine,viewed bool;var views int;if rows.Scan(&id,&ownerID,&name,&avatar,&url,&kind,&caption,&createdAt,&expiresAt,&mine,&viewed,&views)==nil{items=append(items,gin.H{"id":id,"user_id":ownerID,"user_name":name,"avatar_url":avatar,"media_url":url,"media_type":kind,"caption":caption,"created_at":createdAt,"expires_at":expiresAt,"mine":mine,"viewed":viewed,"view_count":views})}}
	c.JSON(http.StatusOK,gin.H{"items":items})
}

func viewStatus(c *gin.Context){userID:=c.GetString("user_id");_,err:=db.Exec(c.Request.Context(),`INSERT INTO status_views(status_id,user_id) SELECT s.id,$2 FROM statuses s WHERE s.id=$1 AND s.expires_at>NOW() AND (s.user_id=$2 OR EXISTS(SELECT 1 FROM contacts c WHERE c.owner_id=$2 AND c.contact_user_id=s.user_id)) ON CONFLICT DO NOTHING`,c.Param("id"),userID);if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"status view could not be saved"});return};c.Status(http.StatusNoContent)}

func listStatusViewers(c *gin.Context){
	rows,err:=db.Query(c.Request.Context(),`SELECT u.id::text,COALESCE(u.full_name,u.username,'GroopX user'),COALESCE(u.avatar_url,''),v.viewed_at
		FROM status_views v JOIN statuses s ON s.id=v.status_id JOIN users u ON u.id=v.user_id
		WHERE v.status_id=$1 AND s.user_id=$2 AND v.user_id<>s.user_id ORDER BY v.viewed_at DESC`,c.Param("id"),c.GetString("user_id"))
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"status viewers could not be loaded"});return};defer rows.Close()
	items:=make([]gin.H,0);for rows.Next(){var id,name,avatar string;var viewedAt time.Time;if rows.Scan(&id,&name,&avatar,&viewedAt)==nil{items=append(items,gin.H{"user_id":id,"name":name,"avatar_url":avatar,"viewed_at":viewedAt})}}
	c.JSON(http.StatusOK,gin.H{"items":items})
}

func deleteStatus(c *gin.Context){tx,err:=db.Begin(c.Request.Context());if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"status could not be deleted"});return};defer tx.Rollback(c.Request.Context());var mediaID string;if tx.QueryRow(c.Request.Context(),`DELETE FROM statuses WHERE id=$1 AND user_id=$2 RETURNING media_id::text`,c.Param("id"),c.GetString("user_id")).Scan(&mediaID)!=nil{c.JSON(http.StatusNotFound,gin.H{"error":"status not found"});return};_,err=tx.Exec(c.Request.Context(),`DELETE FROM media_objects WHERE id=$1`,mediaID);if err!=nil||tx.Commit(c.Request.Context())!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"status could not be deleted"});return};c.Status(http.StatusNoContent)}

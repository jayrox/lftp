# lftp Readme
This Docker will mirror from your seedbox to local unraid server.  After mirroring is complete it will delete the source files and it will extract and *.RAR files in the folder root.

ie.  
If the unraid download directory is /mnt/cache/Downloads/
It will extract all files from /mnt/cache/Downloads/Movie.x264-Group and place it in the same directory.  After it will delete the RAR riles.
It will not extract files in mnt/cache/Downloads/Movie.x264-Group/subs for example.

This needs to connect to an excrypted FTP server.  ie. Explicit FTP over TLS.

Required Environment Variables: 
-------------------------------
FTP_USER
FTP_PASSWORD
FTP_HOST

Other Environment Variables:
----------------------------
FTP_PORT (Default: 990)
FTP_REMOTE_DIR (Default: /.) Typical should be "/home/rtorrentuser/complete/." assuming you move the completed torrents to the complete directory
FTP_CRON_JOB (Default: 0 1 * * *) Specified the time of the download in Cron Syntax.  Default is 1AM.


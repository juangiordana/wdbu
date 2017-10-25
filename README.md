# wdbu

Web developers backup utility is a shell script that utilizes `rsync`, `mysqldump` and `tar` to create incremental backups of websites and their MySQL databases.

## Usage:

`./wdbu.sh <src> <dst>`

This script scans all directories under `src` looking for a user defined configuration file and, if instructed, performs a backup of its files and/or MySQL databases in `dst`.

The script must be run as the `root` user and a valid ~/.my.cnf with administrator credentials must exist in order to export the MySQL databases structure and data.

You can adjust the script to your specific needs by modifying the values under the `Settings` section in `wdbu.sh` with your favorite text editor.

```
$ tree -L 3 /srv/www
/srv/www
├── website_1.com
|   ├── etc
|   │   ├── backup.conf
|   │   └── ...
|   └── ...
├── website_2.com
├── website_3.com
├── ...
└── website_n.com
$ sudo ~/wdbu/wdbu.sh /srv/www /srv/backup
```

Usually you'd run this script from within your `crontab`.

```
# Daily backup at 02:30 AM.
# m h  dom mon dow   command
30 02 * * *  ~/wdbu/wdbu.sh /srv/www /srv/backup
```

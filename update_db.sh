#!/bin/bash
db=https://www.quaddicted.com/reviews/quaddicted_database.xml
fsize=$(wc -c database.xml | awk '{print $1}')
# quaddicted.com's httpd is funky and won't provide ctime/mtime on HEAD
# ...or report content length without providing a range
qlen=$(curl -is --continue 1 "$db" | awk '/content-len/{print $2}' | tr -d [:cntrl:] )

[ -z $qlen -o -z $fsize ] && exit 1
if [ $fsize -lt $qlen ]
      then wget -q -O database.xml $db
   #  echo database changed: $fsize to $qlen
fi

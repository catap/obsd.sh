#!/bin/sh
#
# Copyright (c) 2026 Kirill A. Korinsky <kirill@korins.ky>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

not_found() {
	printf 'HTTP/1.0 404 Not Found\r\nContent-Length: 0\r\n\r\n'
	exit 0
}

bad_request() {
	printf 'HTTP/1.0 400 Bad Request\r\nContent-Length: 0\r\n\r\n'
	exit 0
}

site_answers() {
	printf '\n%s\n%s\n' \
	    "Checksum test for site$site_version.tgz failed. Continue anyway = yes" \
	    "Unverified sets: site$site_version.tgz. Continue without verification = yes"
}

[ $# -ge 2 ] && [ $# -le 3 ] || exit 1
project_dir=$1
httproot=$2
site_version=$3

IFS=' ' read -r method path version || bad_request

case "$method" in
GET|HEAD) ;;
*) bad_request ;;
esac

path=${path%%\?*}
path=${path#/}

content_type=text/plain
append_site_answers=no

case "$path" in
install.conf|upgrade.conf)
	file=$project_dir/install.conf
	[ -z "$site_version" ] || append_site_answers=yes
	;;
disklabel)
	file=$project_dir/disklabel
	;;
pub/OpenBSD/*/*/*)
	set_file=${path##*/}
	case "$set_file" in
	INSTALL.*)
		printf 'HTTP/1.0 200 OK\r\nContent-Length: 0\r\n\r\n'
		exit 0
		;;
	index.txt|SHA256.sig|BUILDINFO)
		file=$httproot/$set_file
		;;
	site*.tgz)
		file=$httproot/site.tgz
		content_type=application/gzip
		;;
	*) not_found ;;
	esac
	;;
*) not_found ;;
esac

[ -f "$file" ] || not_found

set -- $(wc -c < "$file")
length=$1
if [ "$append_site_answers" = yes ]; then
	set -- $(site_answers | wc -c)
	length=$((length + $1))
fi

printf 'HTTP/1.0 200 OK\r\n'
printf 'Content-Type: %s\r\n' "$content_type"
printf 'Content-Length: %s\r\n' "$length"
printf '\r\n'

[ "$method" = HEAD ] && exit 0
cat "$file" || exit 1
[ "$append_site_answers" = no ] || site_answers

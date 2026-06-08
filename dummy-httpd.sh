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

root=${0%/*}
[ "$root" = "$0" ] && root=.

IFS=' ' read -r method path version || bad_request

case "$method" in
GET|HEAD) ;;
*) bad_request ;;
esac

path=${path%%\?*}
path=${path#/}

case "$path" in
install.conf|disklabel)
	file=$root/$path
	;;
*)	not_found
	;;
esac

[ -f "$file" ] || not_found

set -- $(wc -c < "$file")
length=$1

printf 'HTTP/1.0 200 OK\r\n'
printf 'Content-Type: text/plain\r\n'
printf 'Content-Length: %s\r\n' "$length"
printf '\r\n'

[ "$method" = HEAD ] || cat "$file"

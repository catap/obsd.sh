LOCALBASE ?= /usr/local
SYSCONFDIR ?= /etc

SUBST = sed \
	-e 's|@LOCALBASE@|$(LOCALBASE)|g' \
	-e 's|@SYSCONFDIR@|$(SYSCONFDIR)|g'

all: qobsd qobsd.1 qobsd.rc

qobsd: qobsd.in
	$(SUBST) qobsd.in > qobsd
	chmod 755 qobsd

qobsd.1: qobsd.1.in
	$(SUBST) qobsd.1.in > qobsd.1

qobsd.rc: qobsd.rc.in
	$(SUBST) qobsd.rc.in > qobsd.rc

install: all
	install -d "$(DESTDIR)$(LOCALBASE)/bin" \
	    "$(DESTDIR)$(LOCALBASE)/man/man1" \
	    "$(DESTDIR)$(LOCALBASE)/share/qobsd" \
	    "$(DESTDIR)$(LOCALBASE)/share/examples/qobsd/site/etc"
	install -m 755 qobsd "$(DESTDIR)$(LOCALBASE)/bin/qobsd"
	install -m 644 qobsd.1 "$(DESTDIR)$(LOCALBASE)/man/man1/qobsd.1"
	install -m 755 dummy-httpd.sh "$(DESTDIR)$(LOCALBASE)/share/qobsd/"
	install -m 644 openbios-ppc-qobsd-ba2f9b9.elf \
	    openbios-sparc64-qobsd-daa1b25.elf "$(DESTDIR)$(LOCALBASE)/share/qobsd/"
	install -m 755 qobsd.rc \
	    "$(DESTDIR)$(LOCALBASE)/share/examples/qobsd/qobsd.rc"
	install -m 644 qobsd.login disklabel site.perms \
	    u-boot-octeon3-qobsd-boot.pflash u-boot-octeon3-qobsd-install.pflash \
	    "$(DESTDIR)$(LOCALBASE)/share/examples/qobsd/"
	install -m 644 site/install.site "$(DESTDIR)$(LOCALBASE)/share/examples/qobsd/site/"
	install -m 644 site/etc/doas.conf site/etc/mk.conf \
	    "$(DESTDIR)$(LOCALBASE)/share/examples/qobsd/site/etc/"

clean:
	rm -f qobsd qobsd.1 qobsd.rc

.PHONY: all install clean

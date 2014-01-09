# Copyright (C) 2013 Tobias Oetiker

AUTOMAKE_OPTIONS =  foreign

MJ_CLASS = UploadService

BIN = bin/us.pl bin/run.sh

PM :=  $(shell find lib/ -name "*.pm")

POD :=  $(shell find lib/ -name "*.pod")

PUB := $(shell test -d public && find public -type f)

TEMPL := $(shell test -d templates && find templates -type f)

EXTRA_DIST = $(wildcard t/*.t) $(BIN) $(PM) $(POD) $(TEMPL) $(PUB)

YEAR := $(shell date +%Y)
DATE := $(shell date +%Y-%m-%d)

datadir = $(prefix)
nobase_data_DATA = $(PM) $(POD) $(ETC) $(TEMPL) $(PUB)

dist_bin_SCRIPTS = $(BIN)

install-exec-hook:
	[ "$(PERL5LIB)" != "" ] && cd "$(DESTDIR)$(bindir)" && $(PERL) -i -p -e 's{.*# PERL5LIB}{use lib (split /:/, "$(PERL5LIB)"); # PERL5LIB}' *.pl || true
	cd "$(DESTDIR)$(bindir)" && $(PERL) -i -p -e 's{^#!.*perl.*}{#!$(PERL)};' *.pl

dist-hook:
	$(PERL) -i -p -e '"$(PACKAGE_VERSION)" =~ /(\d+)\.(\d+)\.(\d+)/ and $$v = sprintf("%d.%03d%03d",$$1,$$2,$$3) and s/^\$$VERSION\s+=\s+".+?"/\$$VERSION = "$$d"/;'  $(distdir)/lib/$(MJ_CLASS).pm

install-data-local:
	mkdir -p $(DESTDIR)$(HTDOCSDIR)
	echo "#!/bin/sh" > $(DESTDIR)$(HTDOCSDIR)/upload-service.fcgi.dist
	echo "export US_ROOT=/home/oetiker/inbox" >> $(DESTDIR)$(HTDOCSDIR)/upload-service.fcgi.dist
	echo "export US_SECRET_FILE=/etc/uploadsrc.secret" >> $(DESTDIR)$(HTDOCSDIR)/upload-service.fcgi.dist
	echo "export US_ENABLE_DOWNLOAD=0" >> $(DESTDIR)$(HTDOCSDIR)/upload-service.fcgi.dist
	echo "export US_ENABLE_DELETE=0" >> $(DESTDIR)$(HTDOCSDIR)/upload-service.fcgi.dist
	echo "export US_SINGLEUSER=1" >> $(DESTDIR)$(HTDOCSDIR)/upload-service.fcgi.dist
	echo "# export MOJO_TMPDIR=/scratch/upload" >> $(DESTDIR)$(HTDOCSDIR)/upload-service.fcgi.dist
	echo "# mkdir -p $MOJO_TMPDIR" >> $(DESTDIR)$(HTDOCSDIR)/upload-service.fcgi.dist
	echo "# chmod 777 $MOJO_TMPDIR" >> $(DESTDIR)$(HTDOCSDIR)/upload-service.fcgi.dist
	echo 'if [ x\$US_SINGLEUSER = x1 ]; then'>>  $(DESTDIR)$(HTDOCSDIR)/upload-service.fcgi.dist
	echo "  $(prefix)/bin/us.pl fastcgi" >> $(DESTDIR)$(HTDOCSDIR)/upload-service.fcgi.dist
	echo "else " >> $(DESTDIR)$(HTDOCSDIR)/upload-service.fcgi.dist
	echo "  sudo $(prefix)/bin/us.pl fastcgi" >> $(DESTDIR)$(HTDOCSDIR)/upload-service.fcgi.dist
	echo "fi" >> $(DESTDIR)$(HTDOCSDIR)/upload-service.fcgi.dist
	chmod +x $(DESTDIR)$(HTDOCSDIR)/upload-service.fcgi.dist
	[ -f $(DESTDIR)$(HTDOCSDIR)/upload-service.fcgi ] || mv $(DESTDIR)$(HTDOCSDIR)/upload-service.fcgi.dist $(DESTDIR)$(HTDOCSDIR)/upload-service.fcgi
	echo "RewriteBase /~oetiker/uploads" > $(DESTDIR)$(HTDOCSDIR)/.htaccess.dist
	echo "RewriteEngine On" >> $(DESTDIR)$(HTDOCSDIR)/.htaccess.dist
	echo "RewriteCond %{REQUEST_FILENAME} !-f" >> $(DESTDIR)$(HTDOCSDIR)/.htaccess.dist
	echo 'RewriteRule (.*) upload-service.fcgi/\$1 [L]' >> $(DESTDIR)$(HTDOCSDIR)/.htaccess.dist
	[ -f $(DESTDIR)$(HTDOCSDIR)/.htaccess ] || mv $(DESTDIR)$(HTDOCSDIR)/.htaccess.dist  $(DESTDIR)$(HTDOCSDIR)/.htaccess

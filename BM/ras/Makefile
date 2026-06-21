SUBDIRS := mce-test mce-inject ras-tools
INSTALL_SUBDIRS := mce-test mce-inject

# Detect distro-packaged mcelog/rasdaemon (not our own /usr/local installs)
SYSTEM_MCELOG := $(shell rpm -q mcelog 2>/dev/null | grep -v "not installed" || dpkg -s mcelog 2>/dev/null | grep -q "ok installed" && echo yes)
SYSTEM_RASDAEMON := $(shell rpm -q rasdaemon 2>/dev/null | grep -v "not installed" || dpkg -s rasdaemon 2>/dev/null | grep -q "ok installed" && echo yes)

# Build from submodule only if not provided by distro package
ifeq ($(SYSTEM_MCELOG),)
  SUBDIRS += mcelog
  INSTALL_SUBDIRS += mcelog
endif

ifeq ($(SYSTEM_RASDAEMON),)
  SUBDIRS += rasdaemon
  INSTALL_SUBDIRS += rasdaemon
endif

# Filter out targets with custom build rules
GENERIC_SUBDIRS := $(filter-out rasdaemon,$(SUBDIRS))

.PHONY: all
all: $(SUBDIRS)

.PHONY: $(GENERIC_SUBDIRS)
$(GENERIC_SUBDIRS):
	$(MAKE) -C $@

.PHONY: rasdaemon
rasdaemon:
	cd rasdaemon && \
		if [ ! -x ./configure ]; then \
			autoreconf -i; \
		fi && \
		if [ ! -f ./Makefile ]; then \
			./configure --enable-sqlite3 --enable-mce \
				--enable-extlog --enable-memory-failure --enable-memory-ce-pfa; \
		fi && \
		$(MAKE)

.PHONY: install
install:
	for dir in $(INSTALL_SUBDIRS); do \
		$(MAKE) -C $$dir install; \
	done
ifeq ($(SYSTEM_RASDAEMON),)
	@# Install rasdaemon systemd service only if distro doesn't provide one
	@if [ ! -f /usr/lib/systemd/system/rasdaemon.service ]; then \
		install -D -m 644 rasdaemon/misc/rasdaemon.service /etc/systemd/system/rasdaemon.service; \
	fi
	@if [ ! -f /etc/sysconfig/rasdaemon ]; then \
		install -D -m 644 rasdaemon/misc/rasdaemon.env /etc/sysconfig/rasdaemon 2>/dev/null || \
		touch /etc/sysconfig/rasdaemon; \
	fi
	mkdir -p /usr/local/var/lib/rasdaemon
	systemctl daemon-reload
	systemctl enable rasdaemon
	@if systemctl is-active --quiet rasdaemon; then \
		systemctl restart rasdaemon; \
	fi
endif

.PHONY: uninstall
uninstall:
	for dir in $(INSTALL_SUBDIRS); do \
		$(MAKE) -C $$dir uninstall 2>/dev/null || true; \
	done
	@# Stop and remove custom service file if we installed it
	-systemctl stop rasdaemon 2>/dev/null
	-systemctl disable rasdaemon 2>/dev/null
	rm -f /etc/systemd/system/rasdaemon.service
	@# Remove submodule-built rasdaemon data
	rm -rf /usr/local/var/lib/rasdaemon/
	systemctl daemon-reload

.PHONY: clean
clean:
	for dir in $(GENERIC_SUBDIRS); do \
		if [ -f $$dir/Makefile ]; then $(MAKE) -C $$dir clean; fi; \
	done
	@# Use distclean for rasdaemon to remove autotools-generated files
	@# so that configure is re-run on the next build.
	if [ -f rasdaemon/Makefile ]; then $(MAKE) -C rasdaemon distclean; fi

SUBDIRS := mce-test ras-tools

.PHONY: all
all: $(SUBDIRS)

.PHONY: $(SUBDIRS)
$(SUBDIRS):
	$(MAKE) -C $@

.PHONY: install
install:
	for dir in $(SUBDIRS); do \
		if [ "$$dir" = "mce-test" ]; then \
			$(MAKE) -C $$dir install; \
		else \
			echo "Skipping install in $$dir"; \
		fi \
	done

.PHONY: clean
clean:
	for dir in $(SUBDIRS); do \
		$(MAKE) -C $$dir clean; \
	done
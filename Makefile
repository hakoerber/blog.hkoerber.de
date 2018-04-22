REGISTRY := registry.haktec.de
APPNAME := blog-de-haktec
PUSHURL := $(REGISTRY)/$(APPNAME)

BUILD_CONTAINER := $(REGISTRY)/jekyll

.PHONY: all
all: | build image image-push

.PHONY: build
build:
	docker pull $(BUILD_CONTAINER)
	docker run \
		--rm \
		-v $$PWD:/data:Z \
		--workdir /data \
		$(BUILD_CONTAINER) \
		bundle exec \
			jekyll build \
			--config=./_config.yml,./_config.$(TARGET).yml
	# chown $$(id -u):$$(id -g) -R ./_site

.PHONY: image
image:
	docker build \
		--tag $(REGISTRY)/$(APPNAME) \
		--tag $(REGISTRY)/$(APPNAME):master \
		--tag $(REGISTRY)/$(APPNAME):$$(git rev-parse HEAD) \
		--tag $(REGISTRY)/$(APPNAME):$$(git rev-parse --short=8 HEAD) \
		-f Dockerfile .

.PHONY: image-push
image-push:
	docker push $(PUSHURL)

.PHONY: develop
develop:
	bundle exec jekyll serve . --incremental

.PHONY: preview
preview: build
	(cd ./_site/ && python3 -m http.server)

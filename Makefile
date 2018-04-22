REGISTRY := registry.haktec.de
APPNAME := blog
PUSHURL := $(REGISTRY)/$(APPNAME)

BUILD_CONTAINER := $(REGISTRY)/jekyll

.PHONY: all
all: | build image image-push

.PHONY: build
build:
	bundle exec jekyll build --config=./_config.yml,./_config.$(TARGET).yml

.PHONY: image
image:
	docker build \
		--tag $(REGISTRY)/$(APPNAME) \
		--tag $(REGISTRY)/$(APPNAME):$${DRONE_COMMIT_BRANCH} \
		--tag $(REGISTRY)/$(APPNAME):$${DRONE_COMMIT_SHA} \
		-f Dockerfile .

.PHONY: image-push
push:
	docker push $(PUSHURL)

.PHONY: develop
develop:
	bundle exec jekyll serve . --incremental

.PHONY: preview
preview: build
	(cd ./_site/ && python3 -m http.server)

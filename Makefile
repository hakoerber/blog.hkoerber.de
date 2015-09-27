REGISTRY := registry.hkoerber.de
APPNAME := blog
PUSHURL := $(REGISTRY)/$(APPNAME)

.PHONY: build
build-production:
	git diff-index --quiet HEAD || { echo >&2 "Local changes, refusing to build" ; exit 1 ; }
	docker run \
		--rm \
		--net host \
		-v $(PWD):/workdir \
		-w /workdir \
		registry.hkoerber.de/hugo:f216de6b127620641bcaf1d28fe16bf1ea2db884 \
		/app/bin/hugo \
			--baseURL=https://hkoerber.de/ \
			--cleanDestinationDir \
			--minify \
			--destination ./public/
	sudo chown -R $(shell id -u):$(shell id -g) ./public
	sudo chmod -R o+rX ./public

.PHONY: image
image-production: build-production
	git diff-index --quiet HEAD || { echo >&2 "Local changes, refusing to build" ; exit 1 ; }
	docker build \
	  --file ./Dockerfile.nginx \
	  --tag $(REGISTRY)/$(APPNAME):latest \
	  --tag $(REGISTRY)/$(APPNAME):$(shell git rev-parse HEAD) \
	  .


.PHONY: push-production
push-production: image-production
	docker push $(REGISTRY)/$(APPNAME):latest
	docker push $(REGISTRY)/$(APPNAME):$(shell git rev-parse HEAD)

.PHONY: release
release: push-production

.PHONY: preview
preview:
	docker run \
		--rm \
		--net host \
		-v $(PWD):/workdir \
		-w /workdir \
		registry.hkoerber.de/hugo:f000054616d7789202b06872a6535bcb9fd500c9 \
		hugo serve \
			--watch \
			--buildDrafts

REGISTRY := docker.io
APPNAME := hakoerber/blog-de-haktec
PUSHURL := $(REGISTRY)/$(APPNAME)

.PHONY: all
all: | build-image build-image-push image image-push

.PHONY: build-image
build-image:
	sudo docker build --tag hakoerber/jekyll-build -f ./build/Dockerfile ./build/

.PHONY: build-image-push
build-image-push:
	sudo docker push docker.io/hakoerber/jekyll-build

.PHONY: build
build:
	sudo docker run --rm -v $$PWD:/data --workdir /data hakoerber/jekyll-build bundle exec jekyll build --config=./_config.yml,./_config.production.yml
	sudo chown $$(id -u):$$(id -g) -R ./_site

.PHONY: image
image:
	sudo docker build \
		--tag $(REGISTRY)/$(APPNAME) \
		--tag $(REGISTRY)/$(APPNAME):master \
		--tag $(REGISTRY)/$(APPNAME):$$(git rev-parse HEAD) \
		--tag $(REGISTRY)/$(APPNAME):$$(git rev-parse --short=8 HEAD) \
		-f Dockerfile .

.PHONY: image-push
image-push:
	sudo sudo docker push $(PUSHURL)

.PHONY: setup
setup:
	bundle install

.PHONY: develop
develop:
	bundle exec jekyll serve . --incremental


.PHONY: preview
preview: build
	cd ./_site/
	python3 -m http.server

.PHONY: publish
publish: build
	rsync --delete -ri --rsync-path="sudo rsync" ./_site/ haktec.de:/srv/www/blog.haktec.de/
	ssh haktec.de 'sudo restorecon -r -v /srv/www/blog.haktec.de'

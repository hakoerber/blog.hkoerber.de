.PHONY: setup
setup:
	bundle install

.PHONY: develop
develop:
	bundle exec jekyll serve . --incremental

.PHONY: build
build:
	bundle exec jekyll build

.PHONY: preview
preview: build
	cd ./_site/
	python3 -m http.server

.PHONY: publish
publish: build
	rsync --delete -ri ./_site/ 10.10.10.91:/var/lib/blog/public

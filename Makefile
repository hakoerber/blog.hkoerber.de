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
	rsync --delete -ri --rsync-path="sudo rsync" ./_site/ haktec.de:/srv/www/blog.haktec.de/
	ssh haktec.de 'sudo restorecon -r -v /srv/www/blog.haktec.de'

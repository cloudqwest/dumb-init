SHELL=bash
CFLAGS=-std=gnu99 -static -s -Wall -Werror -O3

TEST_PACKAGE_DEPS := build-essential python python-pip procps python-dev python-setuptools

DOCKER_RUN_TEST := docker run -v $(PWD):/mnt:ro
VERSION = $(shell cat VERSION)

.PHONY: build
build: VERSION.h
	$(CC) $(CFLAGS) -o dumb-init dumb-init.c

VERSION.h: VERSION
	echo '// THIS FILE IS AUTOMATICALLY GENERATED' > VERSION.h
	echo '// Run `make VERSION.h` to update it after modifying VERSION.' >> VERSION.h
	xxd -i VERSION >> VERSION.h

.PHONY: clean
clean: clean-tox
	rm -rf dumb-init dist/ *.deb

.PHONY: clean-tox
clean-tox:
	rm -rf .tox

.PHONY: release
release: python-dists
	cd dist && \
		sha256sum --binary dumb-init_$(VERSION)_amd64.deb dumb-init_$(VERSION)_x86_64 > sha256sums

.PHONY: python-dists
python-dists: python-dists-x86_64 

.PHONY: python-dists-%
python-dists-%: VERSION.h
	python setup.py sdist
	docker run \
		--user $$(id -u):$$(id -g) \
		-v `pwd`/dist:/dist:rw \
		quay.io/pypa/manylinux2014_$*:latest \
		bash -exc ' \
			/opt/python/cp38-cp38/bin/pip wheel --wheel-dir /tmp /dist/*.tar.gz && \
			auditwheel repair --wheel-dir /dist /tmp/*.whl --wheel-dir /dist \
		'

.PHONY: builddeb
builddeb:
	debuild --set-envvar=CC=musl-gcc -us -uc -b
	mkdir -p dist
	mv ../dumb-init_*.deb dist/
	# Extract the built binary from the Debian package
	dpkg-deb --fsys-tarfile dist/dumb-init_$(VERSION)_$(shell dpkg --print-architecture).deb | \
		tar -C dist --strip=3 -xvf - ./usr/bin/dumb-init
	mv dist/dumb-init dist/dumb-init_$(VERSION)_$(shell uname -m)

.PHONY: builddeb-docker
builddeb-docker: docker-image
	mkdir -p dist
	docker run --init --user $$(id -u):$$(id -g) -v $(PWD):/tmp/mnt dumb-init-build make builddeb

.PHONY: docker-image
docker-image:
	docker build $(if $(BASE_IMAGE),--build-arg BASE_IMAGE=$(BASE_IMAGE)) -t dumb-init-build .

.PHONY: test
test:
	tox
	tox -e pre-commit

.PHONY: install-hooks
install-hooks:
	tox -e pre-commit -- install -f --install-hooks

#place holders for later
ARCH ?=
MQ_ARCHIVE_ARCH ?=
MQ_ARCHIVE_DEV_ARCH ?=
EXTRA_LABELS ?=
###############################################################################
# Conditional variables - you can override the values of these variables from
# the command line
###############################################################################
# RELEASE shows what release of the container code has been built
RELEASE ?=
# MQ_VERSION is the fully qualified MQ version number to build
MQ_VERSION ?= 9.2.0.0
# MQ_ARCHIVE is the name of the file, under the downloads directory, from which MQ Advanced can
# be installed. Does not apply to MQ Advanced for Developers
MQ_ARCHIVE ?= IBM_MQ_$(MQ_VERSION_VRM)_$(MQ_ARCHIVE_TYPE)_$(MQ_ARCHIVE_ARCH)_NOINST.tar.gz
# MQ_ARCHIVE_DEV is the name of the file, under the downloads directory, from which MQ Advanced
# for Developers can be installed
MQ_ARCHIVE_DEV ?= $(MQ_VERSION)-IBM-MQ-Advanced-for-Developers-Non-Install-$(MQ_ARCHIVE_DEV_TYPE)$(MQ_ARCHIVE_DEV_ARCH).tar.gz
# MQ_IMAGE_ADVANCEDSERVER is the name of the built MQ Advanced image
MQ_IMAGE_ADVANCEDSERVER ?=ibm-mqadvanced-server
# MQ_IMAGE_DEVSERVER is the name of the built MQ Advanced for Developers image
MQ_IMAGE_DEVSERVER ?=ibm-mqadvanced-server-dev
MQ_TAG ?=$(MQ_VERSION)-$(ARCH)
# COMMAND is the container command to run.  "podman" or "docker"
COMMAND ?=$(shell type -p podman 2>&1 >/dev/null && echo podman || echo docker)
# MQ_DELIVERY_REGISTRY_NAMESPACE is the namespace/path on the delivery registry (if required)
MQ_DELIVERY_REGISTRY_NAMESPACE ?=
# REGISTRY_USER is the username used to login to the Red Hat registry
REGISTRY_USER ?=
MQ_ARCHIVE_TYPE=LINUX
MQ_ARCHIVE_DEV_TYPE=Linux
# BUILD_SERVER_CONTAINER is the name of the web server container used at build time
BUILD_SERVER_CONTAINER=build-server
MQ_IMAGE_DEVSERVER_BASE=mqadvanced-server-dev-base
# Variables for versioning
IMAGE_REVISION=$(shell git rev-parse HEAD)
IMAGE_SOURCE=$(shell git config --get remote.origin.url)
EMPTY:=
SPACE:= $(EMPTY) $(EMPTY)
# MQ_VERSION_VRM is MQ_VERSION with only the Version, Release and Modifier fields (no Fix field).  e.g. 9.2.0 instead of 9.2.0.0
MQ_VERSION_VRM=$(subst $(SPACE),.,$(wordlist 1,3,$(subst .,$(SPACE),$(MQ_VERSION))))

ifneq (,$(findstring Microsoft,$(shell uname -r)))
	DOWNLOADS_DIR=$(patsubst /mnt/c%,C:%,$(realpath ./downloads/))
else ifneq (,$(findstring Windows,$(shell echo ${OS})))
	DOWNLOADS_DIR=$(shell pwd)/downloads/
else
	DOWNLOADS_DIR=$(realpath ./downloads/)
endif

# Try to figure out which archive to use from the architecture
ifeq "$(ARCH)" "amd64"
	MQ_ARCHIVE_ARCH=X86-64
	MQ_ARCHIVE_DEV_ARCH=X64
else ifeq "$(ARCH)" "ppc64le"
	MQ_ARCHIVE_ARCH=PPC64LE
else ifeq "$(ARCH)" "s390x"
	MQ_ARCHIVE_ARCH=S390X
endif
ifneq "$(MQ_DELIVERY_REGISTRY_NAMESPACE)" "$(EMPTY)"
	MQ_DELIVERY_REGISTRY_FULL_PATH=$(MQ_DELIVERY_REGISTRY_HOSTNAME)/$(MQ_DELIVERY_REGISTRY_NAMESPACE)
else
	MQ_DELIVERY_REGISTRY_FULL_PATH=$(MQ_DELIVERY_REGISTRY_HOSTNAME)
endif

ifneq "$(RELEASE)" "$(EMPTY)"
	MQ_TAG=$(MQ_VERSION)-$(RELEASE)-$(ARCH)
	EXTRA_LABELS=--label release=$(RELEASE)
	MQ_MANIFEST_TAG=$(MQ_VERSION)-$(RELEASE)
endif
###############################################################################
# Build targets
###############################################################################
.PHONY: default
default: build-devserver
# Build incubating components
.PHONY: incubating
incubating: build-explorer
downloads/$(MQ_ARCHIVE_DEV):
	$(info $(SPACER)$(shell printf $(TITLE)"Downloading IBM MQ Advanced for Developers "$(MQ_VERSION)$(END)))
	$(if $(findstring downloads,$(shell ls downloads)),mkdir downloads)
# Build an MQ image.  The commands used are slightly different between Docker and Podman
define build-mq
	$(if $(findstring docker,$(COMMAND)), @docker network create build,)
	$(if $(findstring docker,$(COMMAND)), @docker run --rm --name $(BUILD_SERVER_CONTAINER) --network build --network-alias build --volume $(DOWNLOADS_DIR):/usr/share/nginx/html:ro --detach docker.io/nginx:alpine,)
	$(eval EXTRA_ARGS=$(if $(findstring docker,$(COMMAND)), --network build --build-arg MQ_URL=http://build:80/$4, --volume $(DOWNLOADS_DIR):/var/downloads --build-arg MQ_URL=file:///var/downloads/$4))
	# Build the new image
	$(COMMAND) build \
	  --tag $1:$2 \
	  --file $3 \
		$(EXTRA_ARGS) \
	  --build-arg IMAGE_REVISION="$(IMAGE_REVISION)" \
	  --build-arg IMAGE_SOURCE="$(IMAGE_SOURCE)" \
	  --build-arg IMAGE_TAG="$1:$2" \
	  --label version=$(MQ_VERSION) \
	  --label name=$1 \
	  --label build-date=$(shell date +%Y-%m-%dT%H:%M:%S%z) \
	  --label architecture="$(ARCH)" \
	  --label run="docker run -d -e LICENSE=accept $1:$2" \
	  --label vcs-ref=$(IMAGE_REVISION) \
	  --label vcs-type=git \
	  --label vcs-url=$(IMAGE_SOURCE) \
	  $(EXTRA_LABELS) \
	  --target $5 \
	  .
	$(if $(findstring docker,$(COMMAND)), @docker kill $(BUILD_SERVER_CONTAINER))
	$(if $(findstring docker,$(COMMAND)), @docker network rm build)
endef
DOCKER_SERVER_VERSION=$(shell docker version --format "{{ .Server.Version }}")
DOCKER_CLIENT_VERSION=$(shell docker version --format "{{ .Client.Version }}")
PODMAN_VERSION=$(shell podman version --format "{{ .Version }}")
.PHONY: command-version
command-version:
# If we're using Docker, then check it's recent enough to support multi-stage builds
ifneq (,$(findstring docker,$(COMMAND)))
	@test "$(word 1,$(subst ., ,$(DOCKER_CLIENT_VERSION)))" -ge "17" || ("$(word 1,$(subst ., ,$(DOCKER_CLIENT_VERSION)))" -eq "17" && "$(word 2,$(subst ., ,$(DOCKER_CLIENT_VERSION)))" -ge "05") || (echo "Error: Docker client 17.05 or greater is required" && exit 1)
	@test "$(word 1,$(subst ., ,$(DOCKER_SERVER_VERSION)))" -ge "17" || ("$(word 1,$(subst ., ,$(DOCKER_SERVER_VERSION)))" -eq "17" && "$(word 2,$(subst ., ,$(DOCKER_CLIENT_VERSION)))" -ge "05") || (echo "Error: Docker server 17.05 or greater is required" && exit 1)
endif
ifneq (,$(findstring podman,$(COMMAND)))
	@test "$(word 1,$(subst ., ,$(PODMAN_VERSION)))" -ge "1" || (echo "Error: Podman version 1.0 or greater is required" && exit 1)
endif
.PHONY: build-devserver
build-devserver: registry-login log-build-env downloads/$(MQ_ARCHIVE_DEV) command-version
	$(info $(shell printf $(TITLE)"Build $(MQ_IMAGE_DEVSERVER):$(MQ_TAG)"$(END)))
	$(call build-mq,$(MQ_IMAGE_DEVSERVER),$(MQ_TAG),Dockerfile-server,$(MQ_ARCHIVE_DEV),mq-dev-server)

.PHONY: registry-login
registry-login:
ifneq ($(REGISTRY_USER),)
	$(COMMAND) login -u $(REGISTRY_USER) -p $(REGISTRY_PASS) registry.redhat.io
endif
.PHONY: log-build-env
log-build-vars:
	$(info $(SPACER)$(shell printf $(TITLE)"Build environment"$(END)))
	@echo ARCH=$(ARCH)
	@echo MQ_VERSION=$(MQ_VERSION)
	@echo MQ_ARCHIVE=$(MQ_ARCHIVE)
	@echo MQ_ARCHIVE_DEV=$(MQ_ARCHIVE_DEV)
	@echo MQ_IMAGE_DEVSERVER=$(MQ_IMAGE_DEVSERVER)
	@echo MQ_IMAGE_ADVANCEDSERVER=$(MQ_IMAGE_ADVANCEDSERVER)
	@echo COMMAND=$(COMMAND)
	@echo REGISTRY_USER=$(REGISTRY_USER)

.PHONY: log-build-env
log-build-env: log-build-vars
	$(info $(SPACER)$(shell printf $(TITLE)"Build environment - $(COMMAND) info"$(END)))
	@echo Command version: $(shell $(COMMAND) --version)
	$(COMMAND) info

include formatting.mk
include formatting.mk

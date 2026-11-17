.PHONY: install lint test sast audit build run scan all

IMAGE ?= secure-notes-api:local

install:
	pip install -r requirements-dev.txt

lint:
	ruff check .

test:
	pytest

sast:
	bandit -r app -c pyproject.toml

audit:
	pip-audit -r requirements.txt --strict

build:
	docker build -t $(IMAGE) .

run: build
	docker run --rm -p 8080:8080 -e API_KEY=local-dev-key \
		--read-only --cap-drop ALL --security-opt no-new-privileges $(IMAGE)

# Requires grype (https://github.com/anchore/grype)
scan: build
	grype $(IMAGE) --fail-on high --only-fixed

all: lint test sast audit

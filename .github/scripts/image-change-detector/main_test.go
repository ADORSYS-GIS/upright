package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/moby/patternmatcher"
	"github.com/moby/patternmatcher/ignorefile"
)

func testMatcher(t *testing.T) *patternmatcher.PatternMatcher {
	t.Helper()

	root, err := filepath.Abs(filepath.Join("..", "..", ".."))
	if err != nil {
		t.Fatalf("find repository root from test directory: %v", err)
	}
	file, err := os.Open(filepath.Join(root, ".dockerignore"))
	if err != nil {
		t.Fatalf("open .dockerignore: %v", err)
	}
	defer file.Close()

	patterns, err := ignorefile.ReadAll(file)
	if err != nil {
		t.Fatalf("parse .dockerignore: %v", err)
	}
	matcher, err := patternmatcher.New(patterns)
	if err != nil {
		t.Fatalf("compile .dockerignore patterns: %v", err)
	}
	return matcher
}

func TestDockerContextAndExplicitBuildInputs(t *testing.T) {
	matcher := testMatcher(t)
	tests := []struct {
		name        string
		paths       []string
		shouldBuild bool
	}{
		{name: "Rails source is included", paths: []string{"app/models/application_record.rb"}, shouldBuild: true},
		{name: "Gemfile lock is included", paths: []string{"Gemfile.lock"}, shouldBuild: true},
		{name: "database migration is included", paths: []string{"db/migrate/new_migration.rb"}, shouldBuild: true},
		{name: "Dockerfile is an explicit input", paths: []string{"Dockerfile"}, shouldBuild: true},
		{name: "dockerignore is an explicit input", paths: []string{".dockerignore"}, shouldBuild: true},
		{name: "image build arguments are an explicit input", paths: []string{".github/image-build-args"}, shouldBuild: true},
		{name: "Docker-included keep files are included", paths: []string{"log/.keep", "tmp/.keep", "tmp/pids/.keep", "tmp/storage/.keep", "storage/.keep", "app/assets/builds/.keep"}, shouldBuild: true},
		{name: "nested config key remains included", paths: []string{"config/credentials/team/private.key"}, shouldBuild: true},
		{name: "nested config deployment file remains included", paths: []string{"config/deploy/team.yml"}, shouldBuild: true},
		{name: "documentation excluded by dockerignore", paths: []string{"README.md"}, shouldBuild: false},
		{name: "Helm changes excluded by dockerignore", paths: []string{"charts/upright/values.yaml"}, shouldBuild: false},
		{name: "unrelated GitHub workflow excluded", paths: []string{".github/workflows/ci.yml"}, shouldBuild: false},
		{name: "publishing workflow logic is not image content", paths: []string{".github/workflows/publish-images.yml"}, shouldBuild: false},
		{name: "Dependabot configuration excluded", paths: []string{".github/dependabot.yml"}, shouldBuild: false},
		{name: "local toolchain and lint files excluded", paths: []string{".ruby-version", "mise.toml", ".rubocop.yml"}, shouldBuild: false},
		{name: "CI-only tools and configuration excluded", paths: []string{"bin/rubocop", "bin/ci", "config/ci.rb", "config/bundler-audit.yml"}, shouldBuild: false},
		{name: "Rails master key excluded", paths: []string{"config/master.key"}, shouldBuild: false},
		{name: "flat credentials key excluded", paths: []string{"config/credentials/production.key"}, shouldBuild: false},
		{name: "generated assets excluded", paths: []string{"app/assets/builds/application.js", "public/assets/application.css"}, shouldBuild: false},
		{name: "local data and logs excluded", paths: []string{"storage/development.sqlite3", "log/production.log", "tmp/restart.txt"}, shouldBuild: false},
		{name: "tests and local compose files excluded", paths: []string{"test/models/example_test.rb", "docker-compose.yml", "docker/seccomp_profile.json"}, shouldBuild: false},
		{name: "mixed change set builds when any input is included", paths: []string{"charts/upright/values.yaml", "app/models/application_record.rb"}, shouldBuild: true},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got, _, err := shouldBuild(test.paths, matcher)
			if err != nil {
				t.Fatalf("shouldBuild returned error: %v", err)
			}
			if got != test.shouldBuild {
				t.Fatalf("shouldBuild(%v) = %t, want %t", test.paths, got, test.shouldBuild)
			}
		})
	}
}

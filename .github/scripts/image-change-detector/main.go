package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/moby/patternmatcher"
	"github.com/moby/patternmatcher/ignorefile"
)

var explicitImageInputs = map[string]struct{}{
	"Dockerfile":               {},
	".dockerignore":            {},
	".github/image-build-args": {},
}

func repositoryRoot() (string, error) {
	output, err := exec.Command("git", "rev-parse", "--show-toplevel").Output()
	if err != nil {
		return "", fmt.Errorf("find repository root: %w", err)
	}
	return strings.TrimSpace(string(output)), nil
}

func changedPaths(root, base, head string) ([]string, error) {
	cmd := exec.Command("git", "-C", root, "diff", "--no-renames", "--name-only", "-z", base, head)
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("list changed files between %s and %s: %w", base, head, err)
	}
	if len(output) == 0 {
		return nil, nil
	}
	paths := strings.Split(strings.TrimSuffix(string(output), "\x00"), "\x00")
	return paths, nil
}

func loadDockerIgnore(root string) (*patternmatcher.PatternMatcher, error) {
	file, err := os.Open(filepath.Join(root, ".dockerignore"))
	if err != nil {
		return nil, fmt.Errorf("open .dockerignore: %w", err)
	}
	defer file.Close()

	patterns, err := ignorefile.ReadAll(file)
	if err != nil {
		return nil, fmt.Errorf("parse .dockerignore: %w", err)
	}
	matcher, err := patternmatcher.New(patterns)
	if err != nil {
		return nil, fmt.Errorf("compile .dockerignore patterns: %w", err)
	}
	return matcher, nil
}

func shouldBuild(paths []string, matcher *patternmatcher.PatternMatcher) (bool, []string, error) {
	var imageInputs []string
	for _, path := range paths {
		path = filepath.ToSlash(filepath.Clean(path))
		if _, explicit := explicitImageInputs[path]; explicit {
			imageInputs = append(imageInputs, path)
			continue
		}

		ignored, err := matcher.MatchesOrParentMatches(path)
		if err != nil {
			return false, nil, fmt.Errorf("match %q against .dockerignore: %w", path, err)
		}
		if !ignored {
			imageInputs = append(imageInputs, path)
		}
	}
	return len(imageInputs) > 0, imageInputs, nil
}

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: image-change-detector <base-sha> <head-sha>")
		os.Exit(2)
	}

	root, err := repositoryRoot()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	paths, err := changedPaths(root, os.Args[1], os.Args[2])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	matcher, err := loadDockerIgnore(root)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	build, imageInputs, err := shouldBuild(paths, matcher)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	if build {
		fmt.Fprintln(os.Stderr, "Image inputs changed:")
		for _, path := range imageInputs {
			fmt.Fprintf(os.Stderr, "  %s\n", path)
		}
		fmt.Println("true")
		return
	}
	fmt.Fprintln(os.Stderr, "No Docker context or image build configuration changes; skipping image build.")
	fmt.Println("false")
}

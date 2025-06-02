# Raif Documentation

This directory contains the Jekyll-based documentation site for Raif, built with the [just-the-docs](https://just-the-docs.github.io/just-the-docs/) theme.

## Local Development

### Prerequisites

- Ruby 3.0+
- Bundler

### Setup

1. Navigate to the docs directory:
   ```bash
   cd docs
   ```

2. Install dependencies:
   ```bash
   bundle install
   ```

3. Serve the site locally:
   ```bash
   bundle exec jekyll serve
   ```

4. Open your browser to `http://localhost:4000/raif`

### Making Changes

- Edit existing pages by modifying the `.md` files
- Add new pages by creating new `.md` files with proper front matter
- The site will automatically rebuild when you save changes (in development mode)

## Site Structure

- `index.md` - Homepage
- `installation.md` - Installation guide
- `tasks.md` - Tasks documentation
- `_config.yml` - Jekyll configuration
- `Gemfile` - Ruby dependencies

## Front Matter

Each page should include front matter like this:

```yaml
---
layout: default
title: Page Title
nav_order: 1
description: "Page description for SEO"
---
```

## Navigation

Pages are automatically added to the navigation based on their `nav_order` value. Lower numbers appear first.

## GitHub Pages Deployment

The site is automatically deployed to GitHub Pages when changes are pushed to the `main` branch. The deployment is handled by the GitHub Actions workflow in `.github/workflows/pages.yml`.

## Theme Documentation

For more information about customizing the theme, see the [just-the-docs documentation](https://just-the-docs.github.io/just-the-docs/).

## Configuration

Key configuration options in `_config.yml`:

- `title` - Site title
- `description` - Site description
- `baseurl` - Base URL for GitHub Pages (usually `/repository-name`)
- `url` - Full URL of the site
- `aux_links` - Links in the top navigation
- `gh_edit_repository` - GitHub repository for "Edit this page" links 
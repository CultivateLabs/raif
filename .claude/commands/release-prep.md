Please prep Raif for a release. To do this:

- Create a branch called `version/v<version-number>-release-prep`
- Remove `(Unreleased)` from CHANGELOG.md
- Remove `-pre` from version file
- Run `bundle install`
- Commit the changes
- Push the branch to `origin`
- Run `gh pr create --base main --title "Prepare for release v<version-number>" --body "Release v<version-number>"`
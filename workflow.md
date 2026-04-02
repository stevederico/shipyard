1. If NEW_REPO is true, scaffold the repo from scratch (create README, package.json, etc.)
2. Implement the task
3. Run tests if they exist
4. If tests fail, fix and re-run (max 3 attempts)
5. Update versioning:
   - Read package.json version and CHANGELOG.md before changing either
   - Bump minor version in package.json (e.g. 1.7.0 → 1.8.0)
   - If that version already exists in CHANGELOG.md, bump again (e.g. → 1.9.0)
   - Add the new version at the top of CHANGELOG.md with a 3-word description (2-space indent, no dash)
6. Stage only the files you modified (never git add . or git add -A)
7. Commit with a descriptive message (no AI attribution, no Co-Authored-By)
8. If NEW_REPO is true, create a GitHub repo: gh repo create PROJECT --private --source=. --push
9. Push the branch: git push origin BRANCH
10. If NEW_REPO is false, open a PR: gh pr create --base BASE_BRANCH
11. Print FACTORY_RESULT:SUCCESS or FACTORY_RESULT:FAILED

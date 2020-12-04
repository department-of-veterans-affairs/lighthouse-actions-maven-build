# lighthouse-actions-maven-build

GitHub action to build Java projects for the Lighthouse program and tooling to help simplify configuring your repository.


```
    - name: Lighthouse maven build
      uses: department-of-veterans-affairs/lighthouse-actions-maven-build@v0
      with:
        nexus-username: ${{ secrets.HEALTH_APIS_RELEASES_NEXUS_USERNAME }}
        nexus-password: ${{ secrets.HEALTH_APIS_RELEASES_NEXUS_PASSWORD }}
        command: non-release
```


#### Commands:

- `non-release`  
  Perform a basic build, skipping release related steps, suchs as building docker images or publishing to Nexus.

See `build.sh --help` for more details.


## Using with CodeQL
A GitHub workflow template is provided. See [templates/codeql.yml](templates/codeql.yml). The `configure-repo.sh` tool can be used to simplify configuring your repository.

1. Clone this repository
2. Update CodeQL workflow
3. Update GitHub secrets
4. Push your changes

```
git clone https://github.com/department-of-veterans-affairs/lighthouse-actions-maven-build.git
lmb=$(pwd)/lighthouse-actions-maven-build
cd ../whereever/your-awesome-repo
git checkout code-scanning
$lmb/configure-repo.sh update-codeql
$lmb/configure-repo.sh update-secrets --nexus-username some-ci-user --nexus-password some-secret
git add .github/workflows/codeql.yml
git checkin -m "Updated to the current CodeQL workflow for Lighthouse projects"
git push -u origin code-scanning
```

See `configure-repo.sh --help` for more details.



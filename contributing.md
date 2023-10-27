# How to Contribute

# Contributing

All untested changes should be made to the `beta` branch.

Once the changes have been tested (see below) create a pull request into the `master` branch.

# Testing Changes

This workflow is used in [lighthouse-daedalus](https://github.com/department-of-veterans-affairs/lighthouse-daedalus) 
as part of the nonrelease and release build workflows. 
To perform testing, update the `lighthouse-release-build.yml` [workflow in the exemplar repo](https://github.com/department-of-veterans-affairs/health-apis-exemplar/blob/master/.github/workflows/lighthouse-release-build.yml)
to use the `release-build-beta.yml` workflow during the `lighthouse-maven-build` job. 
If the job completes successfully, verify the functional changes made had the desired effect.

Pull request overview
---------------------

<!--- DESCRIBE PURPOSE OF THIS PULL REQUEST -->

 - Fixes #ISSUENUMBERHERE (IF RELEVANT)

### Pull Request Author

This pull request makes changes to (select all the apply):
 - [ ] Documentation
 - [ ] Infrastructure (includes apptainer image, buildstock batch, dependencies, continuous integration tests)
 - [ ] Sampling
 - [ ] Workflow Measures
 - [ ] Upgrade Measures
 - [ ] Reporting Measures
 - [ ] Postprocessing

Author pull request checklist:
<!--- Add to this list or remove from it as applicable.  This is a simple templated set of guidelines. -->
 - [ ] Tagged the pull request with the appropriate label (documentation, infrastructure, sampling, workflow measure, upgrade measure, reporting measure, postprocessing) to help categorize changes in the release notes.
 - [ ] Added tests for new measures
 - [ ] Updated measure .xml(s)
 - [ ] Register values added to `comstock_column_definitions.csv`
 - [ ] Both `options_lookup.tsv` files updated
 - [ ] 10k+ test run
 - [ ] Change documentation written
 - [ ] Measure documentation written
 - [ ] ComStock documentation updated
 - [ ] Changes reflected in example `.yml` files
 - [ ] Changes reflected in `README.md` files
 - [ ] Added 'See ComStock License' language to first two lines of each code file
 - [ ] Implements corresponding measure tests and indexing path in `test/measure_tests.txt` or/and `test/resource_measure_tests.txt`
 - [ ] All new and existing tests pass the CI

### Review Checklist

This will not be exhaustively relevant to every PR.
 - [ ] Perform a code review on GitHub
 - [ ] All related changes have been implemented: data and method additions, changes, tests
 - [ ] If fixing a defect, verify by running develop branch and reproducing defect, then running PR and reproducing fix
 - [ ] Reviewed change documentation
 - [ ] Ensured code files contain License reference
 - [ ] Results differences are reasonable
 - [ ] Make sure the newly added measures has been added with tests and indexed properly
 - [ ] CI status: all tests pass

#### ComStock Licensing Language - Add to Beginning of Each Code File
```
# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
```

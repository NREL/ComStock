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

### Pull Request Author Checklist:
<!--- Base checklist. Remove list items that do no apply. -->
 - [ ] Tagged the pull request with the appropriate label (documentation, infrastructure, sampling, workflow measure, upgrade measure, reporting measure, postprocessing) to help categorize changes in the release notes.
 - [ ] Added or edited tests for measures that adequately cover anticipated cases
 - [ ] New or changed register values reflected in `comstock_column_definitions.csv`
 - [ ] Both `options_lookup.tsv` files updated
 - [ ] New measure tests add to to `test/reporting_measure_tests.txt`, `test/workflow_measure_tests.txt`, or `test/upgrade_measure_tests.txt`
 - [ ] Added 'See ComStock License' language to first two lines of each code file
 - [ ] Run rubocop and ensure no ADDITIONAL errors or errors in functions / files edited
 - [ ] Updated measure .xml(s)
 - [ ] Ran 10k+ test run and checked failure rate to make sure no new errors were introduced
 - [ ] Measure documentation written or updated
<!--- Additional items for core changes. -->
 - [ ] ComStock documentation written or updated
 - [ ] Change document written and assigned to a reviewer
 - [ ] Changes reflected in example `.yml` files and `README.md` files
 - [ ] All new / modified functions have docstrings

### Pull Request Reviewer Checklist:
<!--- Base checklist. Remove list items that do no apply. -->
 - [ ] Perform a code review on GitHub
 - [ ] `.yml` and `README.md` files updated
 - [ ] Author had ensured all modified and new functions have docstrings
 - [ ] All changes have been implemented: data, methods, tests, documentation
 - [ ] Measure tests written and adequately cover anticipated cases
 - [ ] Run measure tests and ensure they pass
 - [ ] New measure tests add to to `test/reporting_measure_tests.txt`, `test/workflow_measure_tests.txt`, or `test/upgrade_measure_tests.txt`
 - [ ] Ensured code files contain License reference
 - [ ] (when CI works) Confirm no additional rubocop errors
 - [ ] Check edited measure .xml files updated
 - [ ] (when CI works) CI status: all tests pass
<!--- Additional items for core changes. -->
 - [ ] ComStock documentation adequately describes the new assumptions
 - [ ] Reviewed change documentation, results differences are reasonable, and no new errors introduced
 - [ ] Author has addressed comments in change documentation

#### ComStock Licensing Language - Add to Beginning of Each Code File
```
# ComStock™, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
```

# Scenario

The scenario folder contains specific test files selected for particular scenarios. For example, tests designed for the GraniteRapid + OpenEuler OS platform. These test files can be either plain text files or symbolic links that point to the test files in the feature directory.

## Contents

* Text Files:
Some of the tests are included as plain text files. These files contain the partial of some feature tests.

* Symbolic Links:
Some tests are included as symbolic links. These links point to the relevant test files located in the feature directory, ensuring that the scenario folder remains organized and that tests are not duplicated unnecessarily.

## Purpose
The purpose of this folder is to organize and provide easy access to tests tailored for specific platforms and scenarios.
By having dedicated folders for each scenario, it becomes easier to manage and execute the appropriate tests for different environments.

## How to Use
```
./runtests -f <path_to_scenario_test>
```

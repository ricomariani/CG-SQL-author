# Summary

This test tool verifies that the JSON schema output is well formed according to the expected output rules.
As a consequence the `.y` can be transformed into a railroad diagram for the JSON schema output (and it is).

The idea is that by defining the expected output for each of the JSON schema sections with a grammar
we can test that it is compliant.

This tool is invoked by the main `test.sh` script.

Note that the `.y` file has no actions, we just need to know if the input is compliant or not.  The normal
parser output gives us useful diagnostics that that tell us where we went wrong.

Importantly since this always runs, when a new section is added we know the tests will fail until the grammar
is properly updated.

# License

This source code is licensed under the MIT license found in the
LICENSE file in the root directory of this source tree.

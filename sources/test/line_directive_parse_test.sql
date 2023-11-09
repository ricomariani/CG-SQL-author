-- This is in its own file so that line numbers are only screwed up in this small area
-- In this file syntax errors will not match because of the # directive
-- Keep this file isolated and small.

# 1 "long/path/I/do/not/like"

file_line!();

#line 1 "long/path/I/do/not/like"

set file := @FILE('path/');  -- take starting at path
set file := @FILE('');  -- keep the whole string
set file := @FILE('xxxx');  -- pattern not found, keep it all

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

-- TEST: explain not supported
-- + {explain_stmt}: err
-- + {detail 0} {explain_none}
-- * error: % explain statement is only available in `--dev` mode because its result set may vary between sqlite versions
-- +1 error:
explain select 1;

-- TEST: explain query plan with select
-- + {explain_stmt}: err
-- + {detail 1} {explain_query_plan}
-- * error: % explain statement is only available in `--dev` mode because its result set may vary between sqlite versions
-- +1 error:
explain query plan select * from foo inner join bar where foo.id = 1;

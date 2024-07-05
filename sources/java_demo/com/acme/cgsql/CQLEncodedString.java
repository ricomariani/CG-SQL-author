/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

package com.acme.cgsql;

/*
 * CQLEncodedString hides the string fields in the result set that were marked as vaulted.
 *
 * It has no getter so you can't directly extract the string at all.
 *
 * The way you use this class is you add helper methods to it that directly put the string
 * to where it needs to go, such as logging, or into a text view, or whatever you might need.
 *
 * The idea is that the pieces of code that flow the string to its final destination cannot see
 * its value so they can't do "the wrong thing" with it.  When you are finally ready to do
 * whatever actually needs to be done, that final code calls a helper to do the job.
 *
 * By using this pattern you can easily spot the pieces of code that actually extract the
 * string and restrict them in whatever way you want with simple tools.
 */
public class CQLEncodedString {
  public String mValue;

  public CQLEncodedString(String value) {
    mValue = value;
  }

  @Override
  public String toString() {
    return "[secret]";
  }

  // you add your methods for dealing with encoded strings here
}

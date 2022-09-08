"""
Copyright (C) 2022 The Android Open Source Project

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"""

def get_arg_value(args_list, arg_name):
    """
    Fetches the value of a named argument from the list of args provided by a
    Bazel action. If there are multiple instances of the arg present, this
    function will return the first. This function assumes that the argument
    name is separated from its value via a space.
    Arguments:
        args_list (string[]): The list of arguments provided by the Bazel action.
                           i.e., bazel_action.argv
        arg_name (string): The name of the argument to fetch the value of
    Return:
        The value corresponding to the specified argument name
    """

    # This is to account for different ways of adding arguments to the action
    # when constructing it
    actual_args = " ".join(args_list).split(" ")

    for i in range(1, len(actual_args) - 1):
        if actual_args[i] == arg_name:
            return actual_args[i + 1]
    return None
#!/usr/bin/env python3
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

import json
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: trim_marvin_config.py <marvin-config-path>", file=sys.stderr)
        return 2

    path = sys.argv[1]
    with open(path, encoding="utf-8") as file_handle:
        data = json.load(file_handle)

    cluster = data["zones"][0]["pods"][0]["clusters"][0]
    cluster["hosts"] = cluster["hosts"][:1]

    with open(path, "w", encoding="utf-8") as file_handle:
        json.dump(data, file_handle, indent=4)
        file_handle.write("\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

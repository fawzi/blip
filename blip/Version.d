/// version of the library
///
/// author: fawzi
//
// Copyright 2008-2010 the blip developer group
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
module blip.Version;

enum BlipVersion{
    Major=0, /// changes might be incompatible
    Minor=5, /// changes should be backward compatible
    Sub  =1, /// even numbers are releases, odd are the between releases
}

/// compares the given version to the actual version, returns
/// -1 if the current version is smaller
/// 0 if the versions are equal
/// 1 if the current version is larger than the requested
/// ctfe safe
int blipVersionCompare(int major,int minor,int sub){
    if (major>BlipVersion.Major){
        return -1;
    } else if (major==BlipVersion.Major){
        if (minor>BlipVersion.Minor){
            return -1;
        } else if (minor==BlipVersion.Minor){
            if (sub>BlipVersion.Sub){
                return -1;
            } else if (sub==BlipVersion.Sub){
                return 0;
            }
        }
    }
    return 1;
}

/// a collection containing all rtests of the library
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
module blip.test.BlipTests;
import blip.test.narray.NArrayTests:narrayTests;
import blip.io.Console;
import blip.rtest.RTest;
import blip.test.ContainerTests;
import blip.test.UtilTests:utilTests;
import blip.test.parallel.ParallelTests:parallelTests;
import blip.test.io.IOTests: ioTests;

/// all tests for blip, as template so that they are not instantiated if not used
/// (important especially for NArray).
TestCollection blipTests()(TestCollection superColl=null){
    TestCollection coll=new TestCollection("blip",__LINE__,__FILE__,superColl);
    
    // narrayTests!()(coll); // deactivated this expensive test for now...
    containerTests!()(coll);
    parallelTests!()(coll);
    utilTests!()(coll);
    ioTests!()(coll);
    
    return coll;
}

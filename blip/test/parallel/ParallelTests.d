/// collection with tests for the parallel module
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
module blip.test.parallel.ParallelTests;
import blip.test.parallel.smp.PLoopTests:pLoopTests;
import blip.rtest.RTest;

/// all parallel tests (a template to avoid compilation and instantiation unless really requested)
TestCollection parallelTests()(TestCollection superColl=null){
    TestCollection coll=new TestCollection("parallel",__LINE__,__FILE__,superColl);
    pLoopTests(coll);
    return coll;
}

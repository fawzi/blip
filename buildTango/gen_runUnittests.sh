echo "module runUnittests_ldc;" > runUnittests.d
grep -RE --no-filename '^module [a-zA-Z_.]+ *;' ../../Tango-D2/tango | grep tango | grep -v ".sys." | sed -e 's/module /import /g' >>runUnittests.d

cat >> runUnittests.d <<EOF

import tango.io.Stdout;
import tango.core.Runtime;
import tango.core.tools.TraceExceptions;

bool tangoUnitTester()
{
    uint countFailed = 0;
    uint countTotal = 1;
    Stdout ("NOTE: This is still fairly rudimentary, and will only report the").newline;
    Stdout ("    first error per module.").newline;
    foreach ( m; ModuleInfo )  // _moduleinfo_array )
    {
        if ( m.unitTest) {
            Stdout.format ("{}. Executing unittests in '{}' ", countTotal, m.name).flush;
            countTotal++;
            try {
               m.unitTest();
            }
            catch (Exception e) {
                countFailed++;
                Stdout(" - Unittest failed.").newline;
                Stdout(e.toString()).newline;
                continue;
            }
            Stdout(" - Success.").newline;
        }
    }

    Stdout.format ("{} out of {} tests failed.", countFailed, countTotal - 1).newline;
    return true;
}

static this() {
    Runtime.moduleUnitTester( &tangoUnitTester );
}

void main() {}

EOF


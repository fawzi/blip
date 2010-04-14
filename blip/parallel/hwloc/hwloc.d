/*
 * Bindings to hwloc lib, contains code from the headers of hwloc that is
 *
 * Copyright © 2009 CNRS, INRIA, Université Bordeaux 1
 * released under the BSD license.
 *
 * the interface wrapped is the one of Revision: 1944
 * wrapping by fawzi
 */
module blip.parallel.hwloc.hwloc;
version(noHwloc){} else {
import blip.t.stdc.config;
import blip.t.stdc.stdlib:abort;
import blip.parallel.hwloc.cpuset;
public import blip.parallel.hwloc.cpuset: hwloc_cpuset_t;

version(Windows){
    import tango.sys.win32.Types: HANDLE;
    alias HANDLE hwloc_pid_t;
    alias HANDLE hwloc_thread_t;
} else {
    import tango.stdc.posix.sys.types: pid_t,pthread_t;
    alias pid_t hwloc_pid_t;
    alias pthread_t hwloc_thread_t;
}

/** \file
 * \brief The hwloc API.
 */

/** \defgroup hwlocality_api_version API version
 * @{
 */

/** \brief Indicate at build time which hwloc API version is being used. */
    enum {HWLOC_API_VERSION=0x00010000}

/** @} */



/** \brief Topology context
 *
 * To be initialized with hwloc_topology_init() and built with hwloc_topology_load().
 */
typedef void * hwloc_topology_t;

/** \defgroup hwlocality_types Topology Object Types
 * @{
 */

/** \brief Type of topology object.
 *
 * Do not rely on the ordering of the values as new ones may be defined in the
 * future!  If you need to compare types, use hwloc_compare_types() instead.
 */
enum HWLOC_OBJ {
  SYSTEM, /**< \brief Whole system (may be a cluster of machines).
    * The whole system that is accessible to hwloc.
    * That may comprise several machines in SSI systems
    * like Kerrighed.
    */
  MACHINE,    /**< \brief Machine.
    * A set of processors and memory with cache
    * coherency.
    */
  NODE,   /**< \brief NUMA node.
    * A set of processors around memory which the
    * processors can directly access.
    */
  SOCKET, /**< \brief Socket, physical package, or chip.
    * In the physical meaning, i.e. that you can add
    * or remove physically.
    */
  CACHE,  /**< \brief Data cache.
    * Can be L1, L2, L3, ...
    */
  CORE,   /**< \brief Core.
    * A computation unit (may be shared by several
    * logical processors).
    */
  PU,   /**< \brief (Logical) Processing Unit.
    * An execution unit (may share a core with some
    * other logical processors, e.g. in the case of
    * an SMT core).
    *
    * Objects of this kind are always reported and can
    * thus be used as fallback when others are not.
    */
  GROUP,     /**< \brief Group objects.
    * Objects which do not fit in the above but are
    * detected by hwloc and are useful to take into
    * account for affinity. For instance, some OSes
    * expose their arbitrary processors aggregation this
    * way.
    * way.  And hwloc may insert such objects to group
    * NUMA nodes according to their distances.
    *
    * These objects are ignored when they do not bring
    * any structure.
    */
  MISC,   /**< \brief Miscellaneous objects.
    * Objects without particular meaning, that can e.g. be
    * added by the application for its own use.
    */
}
alias HWLOC_OBJ hwloc_obj_type_t;

///** \brief Maximal value of an object type */
//enum {HWLOC_OBJ_TYPE_MAX=hwloc_obj_type_t.max}

 enum HWLOC_TYPE:int{
     /**< \brief Value returned by hwloc_compare_types when types can not be compared. \hideinitializer */
     UNORDERED=int.max
 }

/** \brief Compare the depth of two object types
 *
 * Types shouldn't be compared as they are, since newer ones may be added in
 * the future.  This function returns less than, equal to, or greater than zero
 * respectively if \p type1 objects usually include \p type2 objects, are the
 * same as \p type2 objects, or are included in \p type2 objects. If the types
 * can not be compared (because neither is usually contained in the other),
 * HWLOC_TYPE_UNORDERED is returned.  Object types containing CPUs can always
 * be compared (usually, a system contains machines which contain nodes which
 * contain sockets which contain caches, which contain cores, which contain
 * processors).
 *
 * \note HWLOC_OBJ_PU will always be the deepest.
 * \note This does not mean that the actual topology will respect that order:
 * e.g. as of today cores may also contain caches, and sockets may also contain
 * nodes. This is thus just to be seen as a fallback comparison method.
 */
extern(C) int hwloc_compare_types (hwloc_obj_type_t type1, hwloc_obj_type_t type2);

/** @} */



/** \defgroup hwlocality_objects Topology Objects
 * @{
 */

 /** \brief Object type-specific Attributes */
 union hwloc_obj_attr_u {
   /** \brief Cache-specific Object Attributes */
   struct hwloc_cache_attr_s {
     ulong size;          /**< \brief Size of cache */
     uint depth;           /**< \brief Depth of cache */
   }
   hwloc_cache_attr_s cache;
   /**< \brief Machine-specific Object Attributes */
   struct hwloc_machine_attr_s {
     char *dmi_board_vendor;       /**< \brief DMI board vendor name */
     char *dmi_board_name;         /**< \brief DMI board model name */
   }
   hwloc_machine_attr_s machine;
   /** \brief Group-specific Object Attributes */
   struct hwloc_group_attr_s {
     uint depth;           /**< \brief Depth of group object */
   }
   hwloc_group_attr_s group;
}

/** \brief Object memory */
struct hwloc_obj_memory_s {
  ulong total_memory; /**< \brief Total memory (in bytes) in this object and its children */
  ulong local_memory; /**< \brief Local memory (in bytes) */

  uint page_types_len; /**< \brief Size of array \p page_types */
  /** \brief Array of local memory page types, \c NULL if no local memory and \p page_types is 0.
   *
   * The array is sorted by increasing \p size fields.
   * It contains \p page_types_len slots.
   */
  struct hwloc_obj_memory_page_type_s {
    ulong size;	/**< \brief Size of pages */
    ulong count;	/**< \brief Number of pages of this size */
  }
  hwloc_obj_memory_page_type_s* page_types;
}


/** \brief Structure of a topology object
 *
 * Applications mustn't modify any field except ::userdata .
 */
struct hwloc_obj {
  /* physical information */
  hwloc_obj_type_t type;        /**< \brief Type of object */
  uint os_index;          /**< \brief OS-provided physical index number */
  char *name;               /**< \brief Object description if any */

  /** \brief Memory attributes */
  hwloc_obj_memory_s memory;

  /** \brief Object type-specific Attributes */
  hwloc_obj_attr_u *attr;

  /* global position */
  uint depth;           /**< \brief Vertical index in the hierarchy */
  uint logical_index;       /**< \brief Horizontal index in the whole list of similar objects,
                     * could be a "cousin_rank" since it's the rank within the "cousin" list below */

  int os_level;			/**< \brief OS-provided physical level, -1 if unknown or meaningless */

  hwloc_obj *next_cousin;    /**< \brief Next object of same type */
  hwloc_obj *prev_cousin;    /**< \brief Previous object of same type */

  /* parent */
  hwloc_obj *parent;     /**< \brief parent, \c NULL if root (system object) */
  uint sibling_rank;        /**< \brief Index in parent's \c children[] array */
  hwloc_obj *next_sibling;   /**< \brief Next object below the same parent*/
  hwloc_obj *prev_sibling;   /**< \brief Previous object below the same parent */

  /* children */
  uint arity;           /**< \brief Number of children */
  hwloc_obj **children;      /**< \brief Children, \c children[0 .. arity -1] */
  hwloc_obj *first_child;    /**< \brief First child */
  hwloc_obj *last_child;     /**< \brief Last child */

  /* misc */
  void *userdata;           /**< \brief Application-given private data pointer, initialized to \c NULL, use it as you wish */

  /* cpuset */
 hwloc_cpuset_t cpuset;		/**< \brief CPUs covered by this object
                                          *
                                          * This is the set of CPUs for which there are PU objects in the topology
                                          * under this object, i.e. which are known to be physically contained in this
                                          * object and known how (the children path between this object and the PU
                                          * objects).
                                          *
                                          * If the HWLOC_TOPOLOGY_FLAG_WHOLE_SYSTEM configuration flag is set, some of
                                          * these CPUs may be offline, or not allowed for binding, see online_cpuset
                                          * and allowed_cpuset.
                                          *
                                          * \note Its value must not be changed, hwloc_cpuset_dup must be used instead.
                                          */
  hwloc_cpuset_t complete_cpuset;       /**< \brief The complete CPU set of logical processors of this object,
                                          *
                                          * This includes not only the same as the cpuset field, but also the CPUs for
                                          * which topology information is unknown or incomplete, and the CPUs that are
                                          * ignored when the HWLOC_TOPOLOGY_FLAG_WHOLE_SYSTEM flag is not set.
                                          * Thus no corresponding PU object may be found in the topology, because the
                                          * precise position is undefined. It is however known that it would be somewhere
                                          * under this object.
                                          *
                                          * \note Its value must not be changed, hwloc_cpuset_dup must be used instead.
                                          */
  hwloc_cpuset_t online_cpuset;         /**< \brief The CPU set of online logical processors
                                          *
                                          * This includes the CPUs contained in this object that are online, i.e. draw
                                          * power and can execute threads.  It may however not be allowed to bind to
                                          * them due to administration rules, see allowed_cpuset.
                                          *
                                          * \note Its value must not be changed, hwloc_cpuset_dup must be used instead.
                                          */
  hwloc_cpuset_t allowed_cpuset;        /**< \brief The CPU set of allowed logical processors
                                          *
                                          * This includes the CPUs contained in this object which are allowed for
                                          * binding, i.e. passing them to the hwloc binding functions should not return
                                          * permission errors.  This is usually restricted by administration rules.
                                          * Some of them may however be offline so binding to them may still not be
                                          * possible, see online_cpuset.
                                          *
                                          * \note Its value must not be changed, hwloc_cpuset_dup must be used instead.
                                          */

  hwloc_cpuset_t nodeset;               /**< \brief NUMA nodes covered by this object or containing this object
                                          *
                                          * This is the set of NUMA nodes for which there are NODE objects in the
                                          * topology under or above this object, i.e. which are known to be physically
                                          * contained in this object or containing it and known how (the children path
                                          * between this object and the NODE objects).
                                          *
                                          * If the HWLOC_TOPOLOGY_FLAG_WHOLE_SYSTEM configuration flag is set, some of
                                          * these nodes may not be allowed for allocation, see allowed_nodeset.
                                          *
                                          * \note Its value must not be changed, hwloc_cpuset_dup must be used instead.
                                          */
  hwloc_cpuset_t complete_nodeset;      /**< \brief The complete NUMA node set of this object,
                                          *
                                          * This includes not only the same as the nodeset field, but also the NUMA
                                          * nodes for which topology information is unknown or incomplete, and the nodes
                                          * that are ignored when the HWLOC_TOPOLOGY_FLAG_WHOLE_SYSTEM flag is not set.
                                          * Thus no corresponding NODE object may be found in the topology, because the
                                          * precise position is undefined. It is however known that it would be
                                          * somewhere under this object.
                                          *
                                          * \note Its value must not be changed, hwloc_cpuset_dup must be used instead.
                                          */
  hwloc_cpuset_t allowed_nodeset;       /**< \brief The set of allowed NUMA memory nodes
                                          *
                                          * This includes the NUMA memory nodes contained in this object which are
                                          * allowed for memory allocation, i.e. passing them to NUMA node-directed
                                          * memory allocation should not return permission errors. This is usually
                                          * restricted by administration rules.
                                          *
                                          * \note Its value must not be changed, hwloc_cpuset_dup must be used instead.
                                          */
}

alias hwloc_obj * hwloc_obj_t;

/** @} */



/** \defgroup hwlocality_creation Create and Destroy Topologies
 * @{
 */

/** \brief Allocate a topology context.
 *
 * \param[out] topologyp is assigned a pointer to the new allocated context.
 *
 * \return 0 on success, -1 on error.
 */
extern(C) int hwloc_topology_init (hwloc_topology_t *topologyp);

/** \brief Build the actual topology
 *
 * Build the actual topology once initialized with hwloc_topology_init() and
 * tuned with ::hwlocality_configuration routine.
 * No other routine may be called earlier using this topology context.
 *
 * \param topology is the topology to be loaded with objects.
 *
 * \return 0 on success, -1 on error.
 *
 * \sa hwlocality_configuration
 */
extern(C) int hwloc_topology_load(hwloc_topology_t topology);

/** \brief Terminate and free a topology context
 *
 * \param topology is the topology to be freed
 */
extern(C) void hwloc_topology_destroy (hwloc_topology_t topology);

/** \brief Run internal checks on a topology structure
 *
 * \param topology is the topology to be checked
 */
extern(C) void hwloc_topology_check(hwloc_topology_t topology);

/** @} */



/** \defgroup hwlocality_configuration Configure Topology Detection
 *
 * These functions can optionally be called between hwloc_topology_init() and
 * hwloc_topology_load() to configure how the detection should be performed,
 * e.g. to ignore some objects types, define a synthetic topology, etc.
 *
 * If none of them is called, the default is to detect all the objects of the
 * machine that the caller is allowed to access.
 *
 * This default behavior may also be modified through environment variables
 * if the application did not modify it already.
 * Setting HWLOC_XMLFILE in the environment enforces the discovery from a XML
 * file as if hwloc_topology_set_xml() had been called.
 * HWLOC_FSROOT switches to reading the topology from the specified Linux
 * filesystem root as if hwloc_topology_set_fsroot() had been called.
 * Finally, HWLOC_THISSYSTEM enforces the return value of
 * hwloc_topology_is_thissystem().
 * @{
 */

/** \brief Ignore an object type.
 *
 * Ignore all objects from the given type.
 * The bottom-level type HWLOC_OBJ_PU may not be ignored.
 * The top-level object of the hierarchy will never be ignored, even if this function
 * succeeds.
 */
extern(C) int hwloc_topology_ignore_type(hwloc_topology_t topology, hwloc_obj_type_t type);

/** \brief Ignore an object type if it does not bring any structure.
 *
 * Ignore all objects from the given type as long as they do not bring any structure:
 * Each ignored object should have a single children or be the only child of its parent.
 * The top-level type HWLOC_OBJ_SYSTEM and bottom-level type HWLOC_OBJ_PU may
 * not be ignored.
 */
extern(C) int hwloc_topology_ignore_type_keep_structure(hwloc_topology_t topology, hwloc_obj_type_t type);

/** \brief Ignore all objects that do not bring any structure.
 *
 * Ignore all objects that do not bring any structure:
 * Each ignored object should have a single children or be the only child of its parent.
 */
extern(C) int hwloc_topology_ignore_all_keep_structure(hwloc_topology_t topology);

/** \brief Flags to be set onto a topology context before load.
 *
 * Flags should be given to hwloc_topology_set_flags().
 */
enum HWLOC_TOPOLOGY_FLAG {
  /* \brief Detect the whole system, ignore reservations and offline settings.
   *
   * Gather all resources, even if some were disabled by the administrator.
   * For instance, ignore Linux Cpusets and gather all processors and memory nodes,
   * and ignore the fact that some resources may be offline.
   */
  WHOLE_SYSTEM = (1<<0),

  /* \brief Assume that the selected backend provides the topology for the
   * system on which we are running.
   *
   * This forces hwloc_topology_is_thissystem to return 1, i.e. makes hwloc assume that
   * the selected backend provides the topology for the system on which we are running,
   * even if it is not the OS-specific backend but the XML backend for instance.
   * This means making the binding functions actually call the OS-specific
   * system calls and really do binding, while the XML backend would otherwise
   * provide empty hooks just returning success.
   *
   * Setting the environment variable HWLOC_THISSYSTEM may also result in the
   * same behavior.
   *
   * This can be used for efficiency reasons to first detect the topology once,
   * save it to an XML file, and quickly reload it later through the XML
   * backend, but still having binding functions actually do bind.
   */
  IS_THISSYSTEM = (1<<1),
}
alias HWLOC_TOPOLOGY_FLAG hwloc_topology_flags_e;

/** \brief Set OR'ed flags to non-yet-loaded topology.
 *
 * Set a OR'ed set of hwloc_topology_flags_e onto a topology that was not yet loaded.
 */
extern(C) int hwloc_topology_set_flags (hwloc_topology_t topology, c_ulong flags);

/** \brief Change the file-system root path when building the topology from sysfs/procfs.
 *
 * On Linux system, use sysfs and procfs files as if they were mounted on the given
 * \p fsroot_path instead of the main file-system root. Setting the environment
 * variable HWLOC_FSROOT may also result in this behavior.
 * Not using the main file-system root causes hwloc_topology_is_thissystem()
 * to return 0.
 *
 * \note For conveniency, this backend provides empty binding hooks which just
 * return success.  To have hwloc still actually call OS-specific hooks, the
 * HWLOC_TOPOLOGY_FLAG_IS_THISSYSTEM has to be set to assert that the loaded
 * file is really the underlying system.
 */
extern(C) int hwloc_topology_set_fsroot(hwloc_topology_t topology, char * fsroot_path);

/** \brief Change which pid the topology is viewed from
 *
 * On some systems, processes may have different views of the machine, for
 * instance the set of allowed CPUs. By default, hwloc exposes the view from
 * the current process. Calling hwloc_topology_set_pid() permits to make it
 * expose the topology of the machine from the point of view of another
 * process.
 *
 * \note hwloc_pid_t is pid_t on unix platforms, and HANDLE on native Windows
 * platforms
 * \note The ENOSYS error is returned on platforms that does not support this
 * feature.
 */
extern(C) int hwloc_topology_set_pid(hwloc_topology_t topology, hwloc_pid_t pid);

/** \brief Enable synthetic topology.
 *
 * Gather topology information from the given \p description
 * which should be a comma separated string of numbers describing
 * the arity of each level.
 * Each number may be prefixed with a type and a colon to enforce the type
 * of a level.  If only some level types are enforced, hwloc will try to
 * choose the other types according to usual topologies, but it may fail
 * and you may have to specify more level types manually.
 *
 * \note For conveniency, this backend provides empty binding hooks which just
 * return success.
 */
extern(C) int hwloc_topology_set_synthetic(hwloc_topology_t topology, char * description);

/** \brief Enable XML-file based topology.
 *
 * Gather topology information the XML file given at \p xmlpath.
 * Setting the environment variable HWLOC_XMLFILE may also result in this behavior.
 * This file may have been generated earlier with lstopo file.xml.
 *
 * \note For conveniency, this backend provides empty binding hooks which just
 * return success.  To have hwloc still actually call OS-specific hooks, the
 * HWLOC_TOPOLOGY_FLAG_IS_THISSYSTEM has to be set to assert that the loaded
 * file is really the underlying system.
 */
extern(C) int hwloc_topology_set_xml(hwloc_topology_t topology, char * xmlpath);

/** \brief Set of flags describing actual support for this topology.
 *
 * This is retrieved with hwloc_topology_get_support() and will be valid until
 * the topology object is destroyed.
 */
extern(C){
struct hwloc_topology_support {
    /** \brief Flags describing actual discovery support for this topology. */
    struct hwloc_topology_discovery_support {
	/** \brief Detecting the number of PU objects is supported. */
	ubyte pu;
    }
    hwloc_topology_discovery_support *discovery;

    /** \brief Flags describing actual binding support for this topology. */
    struct hwloc_topology_cpubind_support {
	/** Binding the whole current process is supported.  */
	ubyte set_thisproc_cpubind;
	/** Getting the binding of the whole current process is supported.  */
	ubyte get_thisproc_cpubind;
	/** Binding a whole given process is supported.  */
	ubyte set_proc_cpubind;
	/** Getting the binding of a whole given process is supported.  */
	ubyte get_proc_cpubind;
	/** Binding the current thread only is supported.  */
	ubyte set_thisthread_cpubind;
	/** Getting the binding of the current thread only is supported.  */
	ubyte get_thisthread_cpubind;
	/** Binding a given thread only is supported.  */
	ubyte set_thread_cpubind;
	/** Getting the binding of a given thread only is supported.  */
	ubyte get_thread_cpubind;
    }
    hwloc_topology_cpubind_support *cpubind;
}
}

/** \brief Retrieve the topology support. */
extern(C) hwloc_topology_support *hwloc_topology_get_support(hwloc_topology_t topology);

/** @} */



/** \defgroup hwlocality_tinker Tinker with topologies.
 * @{
 */

/** \brief Export the topology into an XML file.
 *
 * This file may be loaded later through hwloc_topology_set_xml().
 */
extern(C) void hwloc_topology_export_xml(hwloc_topology_t topology, char *xmlpath);

/** \brief Add a MISC object to the topology
 *
 * A new MISC object will be created and inserted into the topology at the
 * position given by cpuset.
 *
 * cpuset and name will be copied.
 *
 * \return the newly-created object
 */
extern(C) hwloc_obj_t hwloc_topology_insert_misc_object_by_cpuset(hwloc_topology_t topology, hwloc_cpuset_t cpuset, char *name);

/** \brief Add a MISC object to the topology
 *
 * A new MISC object will be created and inserted into the topology at the
 * position given by parent.
 *
 * name will be copied.
 *
 * \return the newly-created object
 */
extern(C) hwloc_obj_t hwloc_topology_insert_misc_object_by_parent(hwloc_topology_t topology, hwloc_obj_t parent, char *name);

/** @} */



/** \defgroup hwlocality_information Get some Topology Information
 * @{
 */

/** \brief Get the depth of the hierachical tree of objects.
 *
 * This is the depth of HWLOC_OBJ_PU objects plus one.
 */
extern(C) uint hwloc_topology_get_depth(hwloc_topology_t  topology);

/** \brief Returns the depth of objects of type \p type.
 *
 * If no object of this type is present on the underlying architecture, or if
 * the OS doesn't provide this kind of information, the function returns
 * HWLOC_TYPE_DEPTH_UNKNOWN.
 *
 * If type is absent but a similar type is acceptable, see also
 * hwloc_get_type_or_below_depth() and hwloc_get_type_or_above_depth().
 */
extern(C) int hwloc_get_type_depth (hwloc_topology_t topology, hwloc_obj_type_t type);
enum HWLOC_TYPE_DEPTH {
    UNKNOWN=-1, /**< \brief No object of given type exists in the topology. */
    MULTIPLE=-2, /**< \brief Objects of given type exist at different depth in the topology. */
}

/** \brief Returns the type of objects at depth \p depth. */
extern(C) hwloc_obj_type_t hwloc_get_depth_type (hwloc_topology_t topology, uint depth);

/** \brief Returns the width of level at depth \p depth */
extern(C) uint hwloc_get_nbobjs_by_depth (hwloc_topology_t topology, uint depth);

/** \brief Returns the width of level type \p type
 *
 * If no object for that type exists, 0 is returned.
 * If there are several levels with objects of that type, -1 is returned.
 */
int hwloc_get_nbobjs_by_type (hwloc_topology_t topology, hwloc_obj_type_t type)
{
    int depth = hwloc_get_type_depth(topology, type);
    if (depth == HWLOC_TYPE_DEPTH.UNKNOWN)
        return 0;
    if (depth == HWLOC_TYPE_DEPTH.MULTIPLE)
        return -1; /* FIXME: agregate nbobjs from different levels? */
    return hwloc_get_nbobjs_by_depth(topology, depth);
}

/** \brief Does the topology context come from this system?
 *
 * \return 1 if this topology context was built using the system
 * running this program.
 * \return 0 instead (for instance if using another file-system root,
 * a XML topology file, or a synthetic topology).
 */
extern(C) int hwloc_topology_is_thissystem(hwloc_topology_t topology);

/** @} */



/** \defgroup hwlocality_traversal Retrieve Objects
 * @{
 */

/** \brief Returns the topology object at index \p index from depth \p depth */
extern(C) hwloc_obj_t hwloc_get_obj_by_depth (hwloc_topology_t topology, uint depth, uint index);

/** \brief Returns the topology object at index \p index with type \p type
 *
 * If no object for that type exists, \c NULL is returned.
 * If there are several levels with objects of that type, \c NULL is returned
 * and ther caller may fallback to hwloc_get_obj_by_depth().
 */
hwloc_obj_t hwloc_get_obj_by_type (hwloc_topology_t topology, hwloc_obj_type_t type, uint index)
{
  int depth = hwloc_get_type_depth(topology, type);
  if (depth == HWLOC_TYPE_DEPTH.UNKNOWN)
    return null;
  if (depth == HWLOC_TYPE_DEPTH.MULTIPLE)
    return null;
  return hwloc_get_obj_by_depth(topology, depth, index);
}

/** @} */



/** \defgroup hwlocality_conversion Object/String Conversion
 * @{
 */

/** \brief Return a stringified topology object type */
extern(C) char * hwloc_obj_type_string (hwloc_obj_type_t type);

/** \brief Return an object type from the string */
extern(C) hwloc_obj_type_t hwloc_obj_type_of_string (char * string);

/** \brief Stringify the type of a given topology object into a human-readable form.
 *
 * It differs from hwloc_obj_type_string() because it prints type attributes such
 * as cache depth.
 *
 * \return how many characters were actually written (not including the ending \\0).
 */
extern(C)int hwloc_obj_type_snprintf(char * string, size_t size, hwloc_obj_t obj,
				   int verbose);
/** \brief Stringify the attributes of a given topology object into a human-readable form.
 *
 * Attribute values are separated by \p separator.
 *
 * Only the major attributes are printed in non-verbose mode.
 *
 * \return how many characters were actually written (not including the ending \\0).
 */
extern(C) int hwloc_obj_attr_snprintf(char * string, size_t size, hwloc_obj_t obj, char * separator,
				   int verbose);

/** \brief Stringify a given topology object into a human-readable form.
 *
 * \note This function is deprecated in favor of hwloc_obj_type_snprintf()
 * and hwloc_obj_attr_snprintf() since it is not very flexible and
 * only prints physical/OS indexes.
 *
 * Fill string \p string up to \p size characters with the description
 * of topology object \p obj in topology \p topology.
 *
 * If \p verbose is set, a longer description is used. Otherwise a
 * short description is used.
 *
 * \p indexprefix is used to prefix the \p os_index attribute number of
 * the object in the description. If \c NULL, the \c # character is used.
 *
 * \return how many characters were actually written (not including the ending \\0).
 */
//extern(C) int hwloc_obj_snprintf(char * string, size_t size,
//                 hwloc_topology_t topology, hwloc_obj_t obj,
//                 char * indexprefix, int verbose);

/** \brief Stringify the cpuset containing a set of objects.
 *
 * \return how many characters were actually written (not including the ending \\0). */
extern(C) int hwloc_obj_cpuset_snprintf(char * str, size_t size, size_t nobj, hwloc_obj_t * objs);

/** @} */



/** \defgroup hwlocality_binding Binding
 *
 * It is often useful to call hwloc_cpuset_singlify() first so that a single CPU
 * remains in the set. This way, the process will not even migrate between
 * different CPUs. Some OSes also only support that kind of binding.
 *
 * \note Some OSes do not provide all ways to bind processes, threads, etc and
 * the corresponding binding functions may fail. ENOSYS is returned when it is
 * not possible to bind the requested kind of object processes/threads). EXDEV
 * is returned when the requested cpuset can not be enforced (e.g. some systems
 * only allow one CPU, and some other systems only allow one NUMA node)
 *
 * The most portable version that
 * should be preferred over the others, whenever possible, is
 *
 * \code
 * hwloc_set_cpubind(topology, set, 0),
 * \endcode
 *
 * as it just binds the current program, assuming it is monothread, or
 *
 * \code
 * hwloc_set_cpubind(topology, set, HWLOC_CPUBIND.THREAD),
 * \endcode
 *
 * which binds the current thread of the current program (which may be
 * multithreaded).
 *
 * \note To unbind, just call the binding function with either a full cpuset or
 * a cpuset equal to the system cpuset.
 * @{
 */

/** \brief Process/Thread binding policy.
 *
 * These flags can be used to refine the binding policy.
 *
 * The default (0) is to bind the current process, assumed to be mono-thread,
 * in a non-strict way.  This is the most portable way to bind as all OSes
 * usually provide it.
 *
 */
enum HWLOC_CPUBIND{
  PROCESS = (1<<0),   /**< \brief Bind all threads of the current multithreaded process.
                      * This may not be supported by some OSes (e.g. Linux). */
  THREAD = (1<<1),        /**< \brief Bind current thread of current process */
  STRICT = (1<<2),        /**< \brief Request for strict binding from the OS
                           *
                           * By default, when the designated CPUs are
                           * all busy while other CPUs are idle, OSes
                           * may execute the thread/process on those
                           * other CPUs instead of the designated CPUs,
                           * to let them progress anyway.  Strict
                           * binding means that the thread/process will
                           * _never_ execute on other cpus than the
                           * designated CPUs, even when those are busy
                           * with other tasks and other CPUs are idle.
                           *
                           * \note Depending on OSes and
                           * implementations, strict binding may not be
                           * possible (implementation reason) or not
                           * allowed (administrative reasons), and the
                           * function will fail in that case.
			   *
			   * When retrieving the binding of a process,
			   * this flag checks whether all its threads
			   * actually have the same binding.
			   * If the flag is not given, the binding of
			   * each thread will be accumulated.
			   *
			   * \note This flag is meaningless when retrieving
			   * the binding of a thread.
			   */
}
alias HWLOC_CPUBIND hwloc_cpubind_policy_t;

/** \brief Bind current process or thread on cpus given in cpuset \p set
 */
extern(C) int hwloc_set_cpubind(hwloc_topology_t topology, hwloc_cpuset_t set,
                int policy);

/** \brief Get current process or thread binding
 */
extern(C) int hwloc_get_cpubind(hwloc_topology_t topology, hwloc_cpuset_t set, int policy);

/** \brief Bind a process \p pid on cpus given in cpuset \p set
 *
 * \note hwloc_pid_t is pid_t on unix platforms, and HANDLE on native Windows
 * platforms
 *
 * \note HWLOC_CPUBIND.THREAD can not be used in \p policy.
 */
extern(C) int hwloc_set_proc_cpubind(hwloc_topology_t topology, hwloc_pid_t pid, hwloc_cpuset_t set, int policy);

/** \brief Get the current binding of process \p pid
 *
 * \note hwloc_pid_t is pid_t on unix platforms, and HANDLE on native Windows
 * platforms
 *
 * \note HWLOC_CPUBIND_THREAD can not be used in \p policy.
 */
extern(C) int hwloc_get_proc_cpubind(hwloc_topology_t topology, hwloc_pid_t pid, hwloc_cpuset_t set, int policy);

/** \brief Bind a thread \p tid on cpus given in cpuset \p set
 *
 * \note hwloc_thread_t is pthread_t on unix platforms, and HANDLE on native
 * Windows platforms
 *
 * \note HWLOC_CPUBIND.PROCESS can not be used in \p policy.
 */
extern(C) int hwloc_set_thread_cpubind(hwloc_topology_t topology, hwloc_thread_t tid, hwloc_cpuset_t set, int policy);

/** \brief Get the current binding of thread \p tid
 *
 * \note hwloc_thread_t is pthread_t on unix platforms, and HANDLE on native
 * Windows platforms
 *
 * \note HWLOC_CPUBIND_PROCESS can not be used in \p policy.
 */
extern(C) int hwloc_get_thread_cpubind(hwloc_topology_t topology, hwloc_thread_t tid, hwloc_cpuset_t set, int policy);

/** @} */

//------ topology/helper: hwloc/helper.h

/** \defgroup hwlocality_helper_types Object Type Helpers
 * @{
 */

/** \brief Returns the depth of objects of type \p type or below
 *
 * If no object of this type is present on the underlying architecture, the
 * function returns the depth of the first "present" object typically found
 * inside \p type.
 */
uint hwloc_get_type_or_below_depth (hwloc_topology_t topology, hwloc_obj_type_t type)
{
  int depth = hwloc_get_type_depth(topology, type);

  if (depth != HWLOC_TYPE_DEPTH.UNKNOWN)
    return depth;

  /* find the highest existing level with type order >= */
  for(depth = hwloc_get_type_depth(topology, HWLOC_OBJ.PU); ; depth--){
    if (hwloc_compare_types(hwloc_get_depth_type(topology, depth), type) < 0)
      return depth+1;
    if (depth==0) assert(0);/* Shouldn't ever happen, as there is always a SYSTEM level with lower order and known depth.  */
  }

}

/** \brief Returns the depth of objects of type \p type or above
 *
 * If no object of this type is present on the underlying architecture, the
 * function returns the depth of the first "present" object typically
 * containing \p type.
 */
uint hwloc_get_type_or_above_depth (hwloc_topology_t topology, hwloc_obj_type_t type)
{
  int depth = hwloc_get_type_depth(topology, type);

  if (depth != HWLOC_TYPE_DEPTH.UNKNOWN)
    return depth;

  /* find the lowest existing level with type order <= */
  for(depth = 0; ; depth++){
    if (hwloc_compare_types(hwloc_get_depth_type(topology, depth), type) > 0)
      return depth-1;
    if (depth>1000) assert(0); /* Shouldn't ever happen, as there is always a PROC level with higher order and known depth.  */
  }
}

/** @} */

/** \brief Returns the top-object of the topology-tree.
 *
 * Its type is typically ::HWLOC_OBJ_MACHINE but it could be different for complex topologies.
 * This function replaces the old deprecated hwloc_get_system_obj().
 */
hwloc_obj_t hwloc_get_root_obj (hwloc_topology_t topology)
{
  return hwloc_get_obj_by_depth (topology, 0, 0);
}
//hwloc_obj_t hwloc_get_system_obj (hwloc_topology_t topology)
//{
//  return hwloc_get_obj_by_depth (topology, 0, 0);
//}


/** \brief Returns the object of type ::HWLOC_OBJ_PU with \p os_index.
 *
 * \note The \p os_index field of object should most of the times only be
 * used for pretty-printing purpose. Type ::HWLOC_OBJ_PU is the only case
 * where \p os_index could actually be useful, when manually binding to
 * processors.
 * However, using CPU sets to hide this complexity should often be preferred.
 */
hwloc_obj_t hwloc_get_pu_obj_by_os_index(hwloc_topology_t topology, uint os_index)
{
  auto depth=hwloc_get_type_depth(topology, HWLOC_OBJ.PU);
  hwloc_obj_t obj=hwloc_get_obj_by_depth (topology, depth, 0);
  while ((obj = obj.next_cousin) !is null)
    if (obj.os_index == os_index)
      return obj;
  return null;
}
}

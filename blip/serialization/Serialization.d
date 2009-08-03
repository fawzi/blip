/// serialization support
/// built borrowing from xpose binary serialization by h3r3tic, but adding protocol
/// like support (inspired by Kris tango Reader/Writer), and support for json and xml like
/// serializations.
/// The serialization can remove cycles. Support for serialization can be added either by hand
/// or via xpose
module blip.serialization.Serialization;
public import blip.serialization.SerializationBase;
//public import blip.serialization.SerializationExpose;
public import blip.serialization.JsonSerialization;
public import blip.serialization.SBinSerialization;
public import blip.serialization.SimpleWrappers;

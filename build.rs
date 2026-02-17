fn main() {
    prost_build::compile_protos(&["proto/time_logging.proto"], &["proto/"]).unwrap();
}

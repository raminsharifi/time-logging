use libmdns::Responder;
use std::thread;

pub fn advertise(port: u16) {
    thread::spawn(move || {
        let responder = Responder::new().expect("failed to create mDNS responder");
        let _service = responder.register(
            "_tl._tcp".into(),
            "tl time-logger".into(),
            port,
            &[],
        );
        loop {
            thread::sleep(std::time::Duration::from_secs(60));
        }
    });
}

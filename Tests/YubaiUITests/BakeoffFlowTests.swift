import XCTest

final class BakeoffFlowTests: XCTestCase {
  private func launch(_ framework: String, _ state: String, _ appearance: String) -> XCUIApplication
  {
    XCUIDevice.shared.appearance = appearance == "dark" ? .dark : .light
    let app = XCUIApplication()
    app.launchArguments = [
      "-YubaiBakeoff", framework, "-YubaiBakeoffState", state, "-AppleInterfaceStyle",
      appearance.capitalized, "--test-ledger", UUID().uuidString,
    ]
    app.launch()
    return app
  }
  func testScreenshots() {
    let original = XCUIDevice.shared.appearance
    defer { XCUIDevice.shared.appearance = original }
    for framework in ["swiftui", "uikit"] {
      for state in ["default", "cats", "time"] {
        for appearance in ["light", "dark"] {
          let app = launch(framework, state, appearance)
          let ready = app.buttons[state == "cats" ? "bakeoff.back" : "bakeoff.key.1"]
          XCTAssertTrue(ready.waitForExistence(timeout: 5))
          let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
          attachment.name = "bakeoff-\(framework)-\(state)-\(appearance)"
          attachment.lifetime = .keepAlways
          add(attachment)
          if state == "default" && appearance == "light" {
            app.buttons["bakeoff.cat.1"].tap()
            XCTAssertTrue(app.buttons["bakeoff.cat.1"].isSelected)
            app.buttons["bakeoff.cat.5"].tap()
            let back = app.buttons["bakeoff.back"]
            let targetY = app.frame.maxY - 560
            let settled = UIFrameWait.run(timeout: 3) {
              guard back.exists, abs(back.frame.minY - targetY) < 1 else { return nil }
              return back.frame
            }
            XCTAssertTrue(settled.stable, settled.description)
            back.tap()
            XCTAssertTrue(back.waitForNonExistence(timeout: 3))
            app.buttons["bakeoff.time"].tap()
            app.buttons["bakeoff.day.昨天"].tap()
            XCTAssertEqual(app.buttons["bakeoff.time"].label, "昨天")
            for key in ["1", ".", "2", "3", "4", "⌫"] { app.buttons["bakeoff.key." + key].tap() }
            XCTAssertEqual(
              app.descendants(matching: .any).matching(identifier: "bakeoff.amount").firstMatch
                .value as? String, "1.2")
          }
          app.terminate()
        }
      }
    }
  }
  private func exercise(_ framework: String) {
    let app = launch(framework, "default", "light")
    for key in ["1", "2", "8", ".", "5"] { app.buttons["bakeoff.key." + key].tap() }
    XCTAssertEqual(
      app.descendants(matching: .any).matching(identifier: "bakeoff.amount").firstMatch.value
        as? String, "128.5")
    app.buttons["bakeoff.type.1"].tap()
    app.buttons["bakeoff.type.0"].tap()
    let header = app.buttons["bakeoff.type.0"].frame
    regrab(from: CGPoint(x: header.midX, y: header.midY))
    let reopen = app.buttons["bakeoff.reopen"]
    XCTAssertTrue(reopen.waitForExistence(timeout: 3))
    reopen.tap()
    XCTAssertTrue(app.buttons["bakeoff.key.1"].waitForExistence(timeout: 3))
  }
  // Separate XCUI drag calls wait for app quiescence between fingers. Schedule the next path
  // from the first lift completion so contact lands during spring-back.
  // These Xcode test-runner selectors stay entirely outside the application.
  private func regrab(from origin: CGPoint) {
    guard let pathClass = NSClassFromString("XCPointerEventPath"),
      let recordClass = NSClassFromString("XCSynthesizedEventRecord"),
      let synthesizer = XCUIDevice.shared.value(forKey: "eventSynthesizer") as? NSObject,
      synthesizer.responds(to: #selector(BakeoffEventSink.synthesize(_:completion:)))
    else {
      XCTFail("XCTest timed pointer events unavailable")
      return
    }
    let paths = unsafeBitCast(pathClass, to: BakeoffTouchPath.Type.self)
    let records = unsafeBitCast(recordClass, to: BakeoffTouchRecord.Type.self)
    func point(_ offset: CGFloat) -> CGPoint { CGPoint(x: origin.x, y: origin.y + offset) }
    let first = paths.init(point: origin, offset: 0)
    first.move(point(325), at: 0.65)
    first.move(point(325), at: 0.76)
    first.lift(at: 0.78)
    let second = paths.init(point: point(230), offset: 0)
    second.move(point(245), at: 0.04)
    second.move(point(650), at: 0.52)
    second.lift(at: 0.53)
    let release = records.init(name: "半程松手", orientation: 1)
    release.add(first)
    let dismiss = records.init(name: "回弹中再次拖动", orientation: 1)
    dismiss.add(second)
    let done = expectation(description: "完成两次拖动")
    let sink = unsafeBitCast(synthesizer, to: BakeoffEventSink.self)
    _ = sink.synthesize(release) { delivered, error in
      XCTAssertTrue(delivered)
      XCTAssertNil(error)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
        _ = sink.synthesize(dismiss) { delivered, error in
          XCTAssertTrue(delivered)
          XCTAssertNil(error)
          done.fulfill()
        }
      }
    }
    wait(for: [done], timeout: 6)
  }
  func testSwiftUIFlow() { exercise("swiftui") }
  func testUIKitFlow() { exercise("uikit") }
}

@objc private protocol BakeoffTouchPath {
  @objc(initForTouchAtPoint:offset:) init(point: CGPoint, offset: Double)
  @objc(moveToPoint:atOffset:) func move(_ point: CGPoint, at time: Double)
  @objc(liftUpAtOffset:) func lift(at time: Double)
}
@objc private protocol BakeoffTouchRecord {
  @objc(initWithName:interfaceOrientation:) init(name: String, orientation: Int)
  @objc(addPointerEventPath:) func add(_ path: BakeoffTouchPath)
}
@objc private protocol BakeoffEventSink {
  @objc(synthesizeEvent:completion:) func synthesize(
    _ record: BakeoffTouchRecord, completion: @escaping (Bool, NSError?) -> Void
  ) -> AnyObject?
}

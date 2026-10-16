import XCTest

/// Progress photos from end to end: taken at a check-in, compared across two
/// check-ins, and deleted until the card no longer mentions them.
///
/// A simulator has no camera, so the app's stand-in supplies each picture;
/// what is under test is the flow around the camera, not the lens.
final class ProgressPhotosUITests: GymTrackUITestCase {

    func testPhotosAreTakenComparedAndDeletedWithNothingLeft() throws {
        app = launchApp(onboarded: true)
        tap(app.tabBars.buttons["Progress"], "the Progress tab")

        // Nothing about photos shows until one exists.
        XCTAssertFalse(app.buttons["measurements.photos"].exists)

        checkInWithAFrontPhoto(first: true)
        checkInWithAFrontPhoto(first: false)

        let photosRow = app.buttons["measurements.photos"]
        scrollUntilVisible(photosRow, in: app.scrollViews.firstMatch)
        tap(photosRow, "the progress photos row")
        require(app.navigationBars["Progress photos"], "the photos sheet")
        require(app.otherElements["progressPhotos.slider"], "the before and after slider")

        tap(app.buttons["Timeline"], "the timeline view")
        for remaining in [1, 0] {
            tap(app.buttons["progressPhotos.delete"], "delete this photo")
            tap(app.buttons["Delete photo"], "the delete confirmation")
            if remaining == 1 {
                require(app.buttons["progressPhotos.delete"], "the photo that is left")
            }
        }
        require(app.staticTexts["No progress photos."], "the empty sheet")
        tap(app.navigationBars["Progress photos"].buttons["Done"], "Done")

        // The check-ins held nothing but the photos, so they went with them.
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.buttons["measurements.photos"])
        waitForExpectations(timeout: Self.stepTimeout)
        XCTAssertFalse(app.buttons["History"].exists, "an empty check-in was kept")
    }

    /// A check-in with only the front photo: the camera opens on that pose,
    /// moves on to the next after the shutter, and is closed from there.
    private func checkInWithAFrontPhoto(first: Bool) {
        let checkIn = button(labelContains: "Check in")
        scrollUntilVisible(checkIn, in: app.scrollViews.firstMatch)
        tap(checkIn, "the check-in button")

        let front = app.buttons["checkIn.photo.frontRelaxed"]
        scrollUntilVisible(front, in: app.collectionViews.firstMatch)
        tap(front, "the front photo tile")
        if first {
            require(element(labelContains: "First front relaxed photo"), "the first-photo caption")
        }
        tap(app.buttons["progressCamera.shutter"], "the shutter")
        expectLabel(app.staticTexts["progressCamera.pose"], "Side")
        tap(app.buttons["progressCamera.close"], "closing the camera")

        require(app.buttons["Retake Front relaxed photo"], "the taken photo's tile")
        tap(app.navigationBars["Check in"].buttons["Save"], "Save")
    }
}

import XCTest
import Foundation
import CryptoKit
import MachO

final class CameraCoachProductionUITests: XCTestCase {
    // AX coordinate conversion can report an exact 44-point frame just below
    // 44. Permit only floating-point roundoff, far below one display pixel.
    private let coordinateRoundoff: CGFloat = 0.000001

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCorrectiveRUPortraitUsesProductionMonitorSurface() {
        let app = launch(
            fixture: "camera.corrective",
            locale: "ru",
            orientation: .portrait
        )
        assertRoot("camera.corrective", in: app)
        assertStableCameraIdentifiers(in: app)
        attachScreenshot(app, named: "camera-corrective-ru-portrait")
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testCorrectiveENLandscapeUsesProductionMonitorSurface() {
        let app = launch(
            fixture: "camera.corrective",
            locale: "en",
            orientation: .landscapeLeft
        )
        assertRoot("camera.corrective", in: app)
        assertStableCameraIdentifiers(in: app)
        attachScreenshot(app, named: "camera-corrective-en-landscape")
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testNoisyFrameOcclusionSignalKeepsAdviceOnSafeEdgeInBothOrientations() {
        let cases: [(UIDeviceOrientation, String)] = [
            (.portrait, "camera-noisy-frame-portrait"),
            (.landscapeLeft, "camera-noisy-frame-landscape")
        ]

        for (orientation, attachmentName) in cases {
            let app = launch(
                fixture: "camera.noisy-frame",
                locale: "en",
                orientation: orientation,
                runtimeSignal: "noisy-frame"
            )
            assertRoot("camera.noisy-frame", in: app)
            assertStableCameraIdentifiers(in: app)
            attachScreenshot(app, named: attachmentName)
            app.terminate()
        }

        XCUIDevice.shared.orientation = .portrait
    }

    func testProductionLiveStateMatrix() {
        let fixtures = [
            "camera.seeking",
            "camera.keep",
            "camera.fallback",
            "camera.starting",
            "camera.failed",
            "camera.explanation",
            "camera.resuming",
            "camera.eco"
        ]

        for fixture in fixtures {
            let app = launch(fixture: fixture, locale: "ru", orientation: .portrait)
            assertRoot(fixture, in: app)
            XCTAssertTrue(
                app.otherElements["camera_coach_live_surface"].waitForExistence(timeout: 3),
                "Missing production monitor surface for \(fixture)"
            )
            attachScreenshot(app, named: fixture.replacingOccurrences(of: ".", with: "-"))
            app.terminate()
        }

        XCUIDevice.shared.orientation = .portrait
    }

    func testDecisionAndRecoveryFixturesReachProductionSurfaceInBothOrientations() {
        // These are DEBUG-only launch fixtures for the fixed Camera Coach
        // state families. They intentionally enter the shipped production
        // monitor surface in a separate app process; the owner-chain unit
        // suite proves the underlying planner/episode/verifier transitions.
        let fixtures: [(fixture: String, orientation: UIDeviceOrientation, state: String)] = [
            ("camera.select-subject", .portrait, "select_subject"),
            ("camera.wait", .landscapeLeft, "wait"),
            ("camera.abstain", .portrait, "abstain"),
            ("camera.corrective", .landscapeLeft, "corrective"),
            ("camera.explanation", .portrait, "explanation"),
            ("camera.movement", .landscapeLeft, "movement"),
            ("camera.verification", .portrait, "verification"),
            ("camera.keep", .landscapeLeft, "keep"),
            ("camera.interrupted", .portrait, "interrupted"),
            ("camera.recovery", .landscapeLeft, "recovery")
        ]

        for (fixture, orientation, state) in fixtures {
            let app = launch(fixture: fixture, locale: "en", orientation: orientation)
            assertRoot(fixture, in: app)
            assertStableCameraIdentifiers(in: app)
            XCTAssertTrue(
                app.otherElements["camera_coach_live_surface"].waitForExistence(timeout: 3),
                "Missing production monitor surface for (fixture)"
            )
            assertSemanticFixtureState(fixture, expectedState: state, in: app)
            if fixture == "camera.explanation" {
                XCTAssertTrue(app.descendants(matching: .any)["camera_coach_explanation"].exists)
            }
            attachScreenshot(app, named: "camera-decision-\(fixture.replacingOccurrences(of: ".", with: "-"))")
            app.terminate()
        }

        XCUIDevice.shared.orientation = .portrait
    }

    func testProductionInterruptedFixtureUsesLifecycleCopy() {
        let app = launch(
            fixture: "camera.interrupted",
            locale: "ru",
            orientation: .portrait
        )
        assertRoot("camera.interrupted", in: app)
        assertStableCameraIdentifiers(in: app)
        attachScreenshot(app, named: "camera-interrupted-ru-portrait")
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testPauseLoadingSuccessEmptyFailureMatrix() {
        let fixtures = [
            "camera.pause-loading",
            "camera.pause-success",
            "camera.pause-empty",
            "camera.pause-failure"
        ]

        for fixture in fixtures {
            let locale = fixture == "camera.pause-success" ? "en" : "ru"
            let app = launch(fixture: fixture, locale: locale, orientation: .portrait)
            assertRoot(fixture, in: app)
            XCTAssertTrue(
                app.otherElements["camera_coach_pause_review"].waitForExistence(timeout: 3),
                "Missing production pause review for \(fixture)"
            )
            XCTAssertTrue(app.buttons["camera_coach_pause"].exists)
            attachScreenshot(app, named: fixture.replacingOccurrences(of: ".", with: "-"))
            app.terminate()
        }

        XCUIDevice.shared.orientation = .portrait
    }

    func testPauseWithoutAssessmentShowsUncertaintyInBothLanguagesWithDynamicType() {
        // This existing presentation fixture has no critique. It exercises the
        // production view's missing-evidence copy, not a successful analysis.
        let cases = [
            (locale: "ru", text: "Недостаточно данных для оценки кадра."),
            (locale: "en", text: "Not enough information to assess this frame.")
        ]
        for item in cases {
            let app = launch(
                fixture: "camera.pause-success",
                locale: item.locale,
                orientation: .portrait,
                reduceMotion: true,
                dynamicType: true
            )
            assertRoot("camera.pause-success", in: app)
            assertVisibleTextFitsViewport(item.text, in: app)
            XCTAssertFalse(app.staticTexts["NO CHANGE NEEDED"].exists)
            XCTAssertFalse(app.staticTexts["ИЗМЕНЕНИЙ НЕ ТРЕБУЕТСЯ"].exists)
            XCTAssertTrue(app.buttons["camera_coach_pause_action"].isHittable)
            attachScreenshot(app, named: "pause-unavailable-\(item.locale)-dynamic-type")
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }

    func testPartialTechnicalCoverageENShowsUncertaintyWithoutFalseCorrection() {
        exercisePartialTechnicalCoverage(locale: "en")
    }

    func testPartialTechnicalCoverageRUShowsUncertaintyWithoutFalseCorrection() {
        exercisePartialTechnicalCoverage(locale: "ru")
    }

    /// Actual generated pixels -> technical measurement -> existing pause
    /// projection -> production view. No neural, provider or media fixture.
    private func exercisePartialTechnicalCoverage(locale: String) {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["SHAFIN_UI_TESTING"] = "1"
        app.launchEnvironment["SETOS_SCENE_BASE_URL"] = "http://camera-partial-coverage-fixture.invalid"
        app.launchEnvironment["SHAFIN_UI_TEST_PARTIAL_COVERAGE"] = "1"
        app.launchArguments = [
            "-SHAFIN_CAMERA_PRODUCTION_FIXTURE", "camera.scene-control",
            "-SHAFIN_SET_LOCALE", locale, "-SHAFIN_SET_REDUCE_MOTION", "1",
            "-SHAFIN_SET_DYNAMIC_TYPE", "xxl"
        ]
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        XCUIDevice.shared.orientation = .portrait
        let review = app.scrollViews["camera_coach_review_scroll"]
        let ready = review.waitForExistence(timeout: 5)
        attachCloudConsentHierarchy(app, named: "partial-coverage-\(locale)-initial-hierarchy")
        attachScreenshot(app, named: "partial-coverage-\(locale)-initial")
        XCTAssertTrue(ready, "The real accepted-pause view must exist")
        XCTAssertFalse(app.staticTexts["camera_scene_control_fixture_error"].exists)
        XCTAssertGreaterThan(app.windows.firstMatch.frame.height, app.windows.firstMatch.frame.width)

        let state = app.staticTexts["camera_partial_coverage_fixture_state"]
        XCTAssertTrue(state.waitForExistence(timeout: 3))
        let observation = XCTAttachment(string: state.label)
        observation.name = "partial-coverage-\(locale)-actual-owner-state"
        observation.lifetime = .keepAlways
        add(observation)
        XCTAssertEqual(state.label,
                       "coverage=partial;reason=sharpnessCauseUnobservable;signalIssues=0;verdict=mixed;actions=0;limitedCoverage=true;fallback=false;verification=none")

        let expectedCopy = locale == "ru"
            ? "Недостаточно данных для оценки кадра."
            : "Not enough information to assess this frame."
        let matchingCopy = review.staticTexts.matching(NSPredicate(format: "label == %@", expectedCopy))
        XCTAssertEqual(matchingCopy.count, 1,
                       "One neutral assessment reason must remain visible without repeating its summary")
        let summary = matchingCopy.element(boundBy: 0)
        revealPauseReviewElement(summary, in: review, app: app, name: "partial-summary-\(locale)")
        let details = review.descendants(matching: .any).matching(identifier: "camera_coach_review_details").firstMatch
        XCTAssertTrue(details.exists)
        XCTAssertEqual(details.staticTexts.matching(NSPredicate(format: "label == %@", expectedCopy)).count, 0)
        XCTAssertFalse(review.staticTexts["camera_coach_review_uncertainty"].exists,
                       "The typed coverage reason is already visible in the primary summary")
        XCTAssertFalse(review.staticTexts["camera_coach_review_status"].exists,
                       "No comparison was attempted for this accepted frame")

        for forbidden in [
            "NO CHANGE NEEDED", "ИЗМЕНЕНИЙ НЕ ТРЕБУЕТСЯ",
            "The frame already suits the chosen task", "Для выбранной задачи кадр уже подходит",
            "FRAME ACCEPTED", "Кадр принят",
            "Refocus on the subject", "Наведи фокус на объект",
            "Not enough data to compare", "Недостаточно данных для сравнения"
        ] {
            XCTAssertFalse(app.staticTexts[forbidden].exists,
                           "Incomplete detail evidence must not produce \(forbidden)")
        }
        let action = review.buttons["camera_coach_pause_action"]
        revealPauseReviewElement(action, in: review, app: app, name: "partial-action-\(locale)")
        assertCloudConsentActionVisible(action, in: app)
        XCTAssertTrue(app.buttons["camera_coach_pause"].isHittable)
        attachCloudConsentHierarchy(app, named: "partial-coverage-\(locale)-final-hierarchy")
        attachScreenshot(app, named: "partial-coverage-\(locale)-xxl-final")

        let humanInput = review.staticTexts["camera_coach_review_human_input"]
        XCTAssertTrue(humanInput.exists)
        XCTAssertEqual(humanInput.label, locale == "ru"
                       ? "Как тебе кажется, получилось?" : "How does it look to you?")
        revealPauseReviewElement(humanInput, in: review, app: app,
                                 name: "partial-human-input-\(locale)")
    }

    func testProductionPauseTransitionAndResumeRoute() {
        let app = launch(fixture: "camera.corrective", locale: "ru", orientation: .portrait)
        assertRoot("camera.corrective", in: app)

        let pauseButton = app.buttons["camera_coach_pause"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 3))
        pauseButton.tap()

        let pauseReview = app.otherElements["camera_coach_pause_review"]
        XCTAssertTrue(pauseReview.waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "РАЗБОР")).firstMatch.waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.buttons["camera_coach_pause_action"].waitForExistence(timeout: 3),
            "the committed pause review must expose its existing accessible action"
        )

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(
            app.otherElements["camera_coach_pause_review"].waitForExistence(timeout: 3),
            "the committed pause review must survive portrait-to-landscape rotation"
        )
        XCTAssertTrue(app.buttons["camera_coach_pause"].exists)

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "РАЗБОР")).firstMatch.waitForExistence(timeout: 3),
            "the committed pause trace must remain inspectable after rotating back"
        )

        app.buttons["camera_coach_pause"].tap()
        XCTAssertTrue(app.otherElements["camera_coach_live_surface"].waitForExistence(timeout: 3))

        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testLensControlStartsCollapsedAndExpandsFromRealFixtureLenses() {
        let app = launch(fixture: "camera.lens-switching", locale: "en", orientation: .landscapeLeft)
        assertRoot("camera.lens-switching", in: app)

        let zoom = app.otherElements["camera_coach_zoom_control"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["WIDE"].exists)
        attachScreenshot(app, named: "camera-lens-collapsed-en-landscape")

        zoom.buttons.firstMatch.tap()
        XCTAssertGreaterThanOrEqual(zoom.buttons.count, 2)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ULTRA")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "TELE")).firstMatch.exists)
        attachScreenshot(app, named: "camera-lens-expanded-en-landscape")

        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testReduceMotionAndDynamicTypeKeepProductionSurfaceReadable() {
        let reduceMotionApp = launch(
            fixture: "camera.corrective",
            locale: "ru",
            orientation: .portrait,
            reduceMotion: true
        )
        assertRoot("camera.corrective", in: reduceMotionApp)
        assertVisibleTextFitsViewport("Сделай предложенное изменение кадра", in: reduceMotionApp)
        attachScreenshot(reduceMotionApp, named: "camera-corrective-ru-portrait-reduce-motion")
        reduceMotionApp.terminate()

        let dynamicTypeApp = launch(
            fixture: "camera.corrective",
            locale: "en",
            orientation: .landscapeLeft,
            dynamicType: true
        )
        assertRoot("camera.corrective", in: dynamicTypeApp)
        XCTAssertTrue(dynamicTypeApp.buttons["camera_coach_pause"].exists)
        assertVisibleTextFitsViewport("Make the suggested frame adjustment", in: dynamicTypeApp)
        attachScreenshot(dynamicTypeApp, named: "camera-corrective-en-landscape-dynamic-type")
        dynamicTypeApp.terminate()

        XCUIDevice.shared.orientation = .portrait
    }

    func testCloudConsentDisclosureFitsAndCanBeCancelledInBothLanguages() {
        let cases = [
            (locale: "ru", title: "Отправить этот кадр для онлайн-анализа?"),
            (locale: "en", title: "Send this frame for online analysis?")
        ]
        for item in cases {
            let app = launchCloudConsent(locale: item.locale, orientation: .portrait)
            let title = app.staticTexts["camera_cloud_consent_title"]
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            XCTAssertEqual(title.label, item.title)
            XCTAssertTrue(app.images["camera_cloud_preview"].exists)
            let cancel = app.buttons["camera_cloud_decline"]
            attachCloudConsentHierarchy(app, named: "camera-cloud-consent-\(item.locale)-top-hierarchy")
            XCTAssertEqual(app.buttons.matching(identifier: "camera_cloud_decline").count, 1)
            XCTAssertTrue(app.scrollViews["camera_cloud_consent_scroll"].exists)
            assertCloudConsentActionVisible(cancel, in: app)
            attachScreenshot(app, named: "camera-cloud-consent-\(item.locale)-xxl-top")
            cancel.tap()
            let state = app.staticTexts["camera_cloud_fixture_state"]
            XCTAssertTrue(state.waitForExistence(timeout: 4))
            XCTAssertEqual(state.label, "cancelled")
            XCTAssertFalse(app.staticTexts["approval-callback-received"].exists)
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }

    func testCloudConsentDisclosureReachesApprovalInLandscapeWithDynamicType() throws {
        try prepareSimulatorIPadFullScreenLayout()
        let app = launchCloudConsent(locale: "en", orientation: .landscapeLeft)
        XCTAssertTrue(app.staticTexts["camera_cloud_consent_title"].waitForExistence(timeout: 5))
        let send = app.buttons["camera_cloud_send"]
        let scroll = app.scrollViews["camera_cloud_consent_scroll"]
        attachCloudConsentHierarchy(app, named: "camera-cloud-consent-en-landscape-top-hierarchy")
        XCTAssertTrue(scroll.waitForExistence(timeout: 3))
        XCTAssertEqual(app.scrollViews.matching(identifier: "camera_cloud_consent_scroll").count, 1)
        let cancel = app.buttons["camera_cloud_decline"]
        assertCloudConsentActionVisible(cancel, in: app)
        for _ in 0..<20 {
            if send.isHittable { break }
            scroll.swipeUp()
            assertCloudConsentActionVisible(cancel, in: app)
        }
        attachCloudConsentHierarchy(app, named: "camera-cloud-consent-en-landscape-bottom-hierarchy")
        XCTAssertTrue(send.isHittable, "The complete disclosure must remain scrollable to its action at XXL")
        XCTAssertEqual(app.buttons.matching(identifier: "camera_cloud_send").count, 1)
        assertCloudConsentActionVisible(send, in: app)
        assertCloudConsentActionVisible(cancel, in: app)
        attachScreenshot(app, named: "camera-cloud-consent-en-xxl-landscape-bottom")
        send.tap()
        let state = app.staticTexts["camera_cloud_fixture_state"]
        XCTAssertTrue(state.waitForExistence(timeout: 4))
        XCTAssertEqual(state.label, "approval-callback-received",
                       "This checks only the synthetic fixture callback; no network request exists")
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testSceneControlRuntimeRUPauseAnswersReachPlannerAndReset() {
        let app = launchSceneControl(locale: "ru", orientation: .portrait)
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let open = app.buttons["camera_scene_control_open"]
        XCTAssertTrue(open.waitForExistence(timeout: 6), "The actual accepted-pause footer must offer optional scene control")
        XCTAssertTrue(open.isHittable)
        XCTAssertGreaterThanOrEqual(open.frame.height + coordinateRoundoff, 44)
        assertSceneControlPauseLayout(in: app)
        assertPauseReviewTextAndActionReachable(in: app, locale: "ru")
        assertSceneControlState(in: app, objects: "unknown", participants: "unknown", lighting: "unknown", physical: false)
        open.tap()
        XCTAssertTrue(app.buttons["camera_scene_control_done"].waitForExistence(timeout: 4))
        for category in ["objects", "participants", "lighting"] {
            let picker = app.buttons["camera_scene_control_" + category]
            XCTAssertTrue(picker.exists)
            XCTAssertTrue((picker.value as? String ?? picker.label).contains("Не указано"))
        }
        selectSceneControl("objects", answer: "Да", in: app)
        attachScreenshot(app, named: "scene-control-runtime-ru-objects-allowed")
        app.buttons["camera_scene_control_done"].tap()
        assertSceneControlState(in: app, objects: "allowed", participants: "unknown", lighting: "unknown", physical: true)
        open.tap()
        selectSceneControl("participants", answer: "Нет", in: app)
        selectSceneControl("objects", answer: "Не указано", in: app)
        app.buttons["camera_scene_control_done"].tap()
        assertSceneControlState(in: app, objects: "unknown", participants: "forbidden", lighting: "unknown", physical: false)
        open.tap()
        let reset = app.buttons["camera_scene_control_reset"]
        XCTAssertTrue(reset.isHittable)
        reset.tap()
        app.buttons["camera_scene_control_done"].tap()
        assertSceneControlState(in: app, objects: "unknown", participants: "unknown", lighting: "unknown", physical: false)
        attachScreenshot(app, named: "scene-control-runtime-ru-reset")
    }

    func testImagePlacementRUEditorCancelSaveAndResetOnActualPause() {
        let app = launchSceneControl(locale: "ru", orientation: .portrait, activePlacement: true)
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        exerciseImagePlacementEditor(in: app, locale: "ru")
    }

    func testImagePlacementENLandscapeXXLUsesAcceptedImageEditor() {
        let app = launchSceneControl(locale: "en", orientation: .landscapeLeft, dynamicType: true, activePlacement: true)
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        assertSceneControlLandscape(in: app)
        exerciseImagePlacementEditor(in: app, locale: "en")
    }

    private func exerciseImagePlacementEditor(in app: XCUIApplication, locale: String) {
        // This literal is inside the exercised method, so its presence proves
        // execution reached this revision rather than an older helper body.
        XCTAssertTrue(recordPlacementRuntimeIdentity(
            revision: "placement.exercise.next-take-review.identity.v2", locale: locale
        ), "The executing test image must have an unambiguous loaded identity matching its disk image")
        let assessment = app.staticTexts["camera_placement_fixture_assessment"]
        XCTAssertTrue(assessment.waitForExistence(timeout: 4))
        let originalAssessment = assessment.label
        XCTAssertTrue(originalAssessment.contains("verdict=good"))
        XCTAssertTrue(originalAssessment.contains("verification=none"))
        assertPlacementOriginalReview(in: app, locale: locale)
        let open = app.buttons["camera_placement_open"]
        XCTAssertTrue(open.waitForExistence(timeout: 6))
        XCTAssertTrue(open.isHittable)
        XCTAssertGreaterThanOrEqual(open.frame.height + coordinateRoundoff, 44)
        open.tap()
        let apply = app.buttons["camera_placement_apply"]
        let cancel = app.buttons["camera_placement_cancel"]
        XCTAssertTrue(apply.waitForExistence(timeout: 4))
        XCTAssertFalse(apply.isEnabled)
        XCTAssertGreaterThanOrEqual(apply.frame.height + coordinateRoundoff, 44)
        XCTAssertGreaterThanOrEqual(cancel.frame.height + coordinateRoundoff, 44)
        let scroll = app.scrollViews["camera_placement_scroll"]
        let image = app.images["camera_placement_image"]
        // This fixture's accepted image is square. The primary observed box is
        // x=.25...5, display-y=.4...8. End a real scroll inside that box: the old
        // zero-distance drag handler incorrectly selected it on release.
        let fit = revealPlacementImage(in: app, scroll: scroll)
        let beforeScrollY = image.frame.minY
        placementDrag(in: app,
                      from: CGPoint(x: fit.minX + fit.width * 0.375, y: fit.minY + fit.height * 0.78),
                      to: CGPoint(x: fit.minX + fit.width * 0.375, y: fit.minY + fit.height * 0.6))
        if locale == "en" {
            // This landscape XXL journey has real overflowing content. The
            // portrait RU editor fits its viewport, so it must not be required
            // to produce a scroll displacement where there is nothing to scroll.
            let scrolled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                abs(image.frame.minY - beforeScrollY) > 8
            }, object: image)
            XCTAssertEqual(XCTWaiter.wait(for: [scrolled], timeout: 2), .completed,
                           "Dragging over the image in selection mode must scroll overflowing content")
        }
        XCTAssertFalse(apply.isEnabled, "Scrolling over a known box must not select it")
        let manual = app.buttons["camera_placement_manual"]
        revealPlacementControl(manual, in: scroll, app: app)
        XCTAssertTrue(manual.isHittable)
        manual.tap()
        XCTAssertTrue(apply.isEnabled)
        cancel.tap()
        open.tap()
        XCTAssertTrue(apply.waitForExistence(timeout: 4))
        XCTAssertFalse(apply.isEnabled, "Cancel cannot commit the locally edited ROI")
        revealPlacementControl(manual, in: scroll, app: app)
        XCTAssertTrue(manual.isHittable)
        manual.tap()
        let leftEdge = app.sliders["camera_placement_coordinate_0"]
        revealPlacementControl(leftEdge, in: scroll, app: app)
        XCTAssertTrue(leftEdge.isHittable)
        leftEdge.adjust(toNormalizedSliderPosition: 0.1)
        let sliderEditedValue = leftEdge.value as? String
        XCTAssertNotNil(sliderEditedValue)
        let drawingFit = revealPlacementImage(in: app, scroll: scroll)
        let beforeDrawY = image.frame.minY
        placementDrag(in: app,
                      from: CGPoint(x: drawingFit.minX + drawingFit.width * 0.15,
                                    y: drawingFit.minY + drawingFit.height * 0.6),
                      to: CGPoint(x: drawingFit.minX + drawingFit.width * 0.45,
                                  y: drawingFit.minY + drawingFit.height * 0.75))
        XCTAssertEqual(image.frame.minY, beforeDrawY, accuracy: 0.5,
                       "Explicit manual drawing must own the image drag")
        XCTAssertTrue(apply.isEnabled, "A drawn rectangle wholly inside the accepted image is valid")
        attachScreenshot(app, named: "accepted-image-placement-manual-drag-\(locale)")
        revealPlacementControl(leftEdge, in: scroll, app: app)
        XCTAssertTrue(leftEdge.isHittable)
        let drawnValue = leftEdge.value as? String
        XCTAssertNotNil(drawnValue)
        XCTAssertNotEqual(drawnValue, sliderEditedValue, "The drawing must update the actual ROI coordinates")
        apply.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 4))
        assertSceneControlPauseLayout(in: app)
        assertPlacementReviewInstructionAndReference(in: app, locale: locale,
                                                    originalDrawingSize: drawingFit.size)
        XCTAssertEqual(assessment.label, originalAssessment,
                       "The chosen goal must not change the accepted verdict, issues or verification status")
        XCTAssertTrue(open.isHittable)
        XCTAssertGreaterThanOrEqual(open.frame.height + coordinateRoundoff, 44)
        if app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height {
            let sceneControl = app.buttons["camera_scene_control_open"]
            XCTAssertEqual(open.frame.midY, sceneControl.frame.midY, accuracy: 0.5,
                           "The two full titles fit one landscape footer row")
        }
        attachScreenshot(app, named: "accepted-image-placement-saved-pause-\(locale)")
        open.tap()
        XCTAssertTrue(apply.waitForExistence(timeout: 4))
        XCTAssertTrue(apply.isEnabled, "Saved ROI must return from the actual accepted-pause owner")
        XCTAssertTrue(app.staticTexts["camera_placement_saved_goal"].exists)
        revealPlacementControl(leftEdge, in: scroll, app: app)
        // Preserve the complete presented sheet tree: XCTest's synthesized
        // Window snapshots can contain only the underlying camera surface.
        attachCloudConsentHierarchy(app, named: "accepted-image-placement-reopened-coordinate-\(locale)")
        attachScreenshot(app, named: "accepted-image-placement-reopened-coordinate-\(locale)")
        XCTAssertTrue(leftEdge.isHittable)
        XCTAssertEqual(leftEdge.value as? String, drawnValue,
                       "Reopening must retain the actual saved manually drawn region")
        let reset = app.buttons["camera_placement_reset"]
        revealPlacementControl(reset, in: scroll, app: app)
        XCTAssertTrue(reset.isHittable)
        reset.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 4))
        assertPlacementOriginalReview(in: app, locale: locale)
        XCTAssertFalse(app.images["camera_placement_review_marker"].exists)
        XCTAssertEqual(assessment.label, originalAssessment)
        open.tap()
        XCTAssertTrue(apply.waitForExistence(timeout: 4))
        XCTAssertFalse(apply.isEnabled)
        cancel.tap()
    }

    private func assertPlacementOriginalReview(in app: XCUIApplication, locale: String) {
        let expected = locale == "ru" ? "Для выбранной задачи кадр уже подходит"
            : "The frame already suits the chosen task"
        let review = app.scrollViews["camera_coach_review_scroll"]
        let text = review.staticTexts.matching(NSPredicate(format: "label == %@", expected)).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 3))
        revealPauseReviewElement(text, in: review, app: app, name: "placement-original-\(locale)")
        assertPlacementReviewStatus(in: app, locale: locale)
    }

    private func assertPlacementReviewStatus(in app: XCUIApplication, locale: String) {
        let review = app.scrollViews["camera_coach_review_scroll"]
        XCTAssertTrue(review.exists)
        // These retained GOOD/placement fixtures have verification=none.
        // A comparison warning would invent a check that was never attempted.
        XCTAssertFalse(review.staticTexts["camera_coach_review_status"].exists)
        let unattemptedCopy = locale == "ru" ? "Недостаточно данных для сравнения"
            : "Not enough data to compare"
        XCTAssertFalse(review.staticTexts[unattemptedCopy].exists)
    }

    private func assertPlacementReviewInstructionAndReference(
        in app: XCUIApplication, locale: String, originalDrawingSize: CGSize
    ) {
        let review = app.scrollViews["camera_coach_review_scroll"]
        let expected = locale == "ru"
            ? "Для следующего кадра измените кадрирование, чтобы выбранная область оказалась ближе к центру."
            : "For the next frame, reframe so the selected area appears closer to the center."
        let instruction = review.staticTexts.matching(NSPredicate(format: "label == %@", expected)).firstMatch
        XCTAssertTrue(instruction.waitForExistence(timeout: 3))
        revealPauseReviewElement(instruction, in: review, app: app, name: "placement-next-take-\(locale)")
        let action = review.buttons["camera_coach_pause_action"]
        revealPauseReviewElement(action, in: review, app: app, name: "placement-more-take-\(locale)")
        XCTAssertEqual(action.label, locale == "ru" ? "ЕЩЁ ДУБЛЬ" : "ONE MORE TAKE")
        XCTAssertTrue(action.isHittable)
        XCTAssertGreaterThanOrEqual(action.frame.height + coordinateRoundoff, 44)
        let image = app.images["camera_placement_review_image"]
        XCTAssertTrue(image.waitForExistence(timeout: 3))
        revealPauseReviewElement(image, in: review, app: app, name: "placement-observed-image-\(locale)")
        let marker = app.images["camera_placement_review_marker"]
        XCTAssertTrue(marker.exists)
        let frame = image.frame
        // Independent screen-space expectation from the actual manual gesture
        // above: compare the observed ROI, never a centred destination or a
        // geometry value read back from the projection implementation.
        let accuracy = max(1, frame.width / originalDrawingSize.width * 1.5)
        // AX reports rendered ink. The reference's outer black 4-point stroke
        // extends 2 points on each side of its observed-ROI centerline.
        let observedROI = marker.frame.insetBy(dx: 2, dy: 2)
        XCTAssertEqual(observedROI.minX, frame.minX + frame.width * 0.15, accuracy: accuracy)
        XCTAssertEqual(observedROI.minY, frame.minY + frame.height * 0.6, accuracy: accuracy)
        XCTAssertEqual(observedROI.width, frame.width * 0.3, accuracy: accuracy)
        XCTAssertEqual(observedROI.height, frame.height * 0.15, accuracy: accuracy)
        XCTAssertTrue(frame.insetBy(dx: -accuracy, dy: -accuracy).contains(observedROI))
        XCTAssertGreaterThan(abs(observedROI.midX - frame.midX), frame.width * 0.1,
                             "The displayed outline must not substitute the desired centred position")
        attachScreenshot(app, named: "placement-selected-observation-\(locale)")
        assertPlacementReviewStatus(in: app, locale: locale)
    }

    private func recordPlacementRuntimeIdentity(revision: String, locale: String) -> Bool {
        let bundle = Bundle(for: CameraCoachProductionUITests.self)
        var record: [String: Any] = [
            "source_protocol_revision": revision, "test_name": name, "locale": locale,
            "process_id": ProcessInfo.processInfo.processIdentifier,
            "process_name": ProcessInfo.processInfo.processName,
            "bundle_path": bundle.bundleURL.path,
            "bundle_identifier": bundle.bundleIdentifier ?? "",
            "source_path": #filePath
        ]
        var errors: [String] = []
        var loadedImages: [[String: Any]] = []
        var matchingUUIDs: [String] = []
        var diskUUID: String?
        if let executable = bundle.executableURL {
            let canonicalPath = executable.resolvingSymlinksInPath().standardizedFileURL.path
            record["executable_path"] = executable.path
            record["canonical_executable_path"] = canonicalPath
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: executable.path)
                guard let size = attributes[.size] as? NSNumber,
                      size.int64Value > 0, size.int64Value <= 64 * 1024 * 1024 else {
                    throw placementIdentityError("Test executable is missing or exceeds the 64 MiB diagnostic bound")
                }
                let data = try Data(contentsOf: executable, options: .mappedIfSafe)
                guard !data.isEmpty, data.count <= 64 * 1024 * 1024 else {
                    throw placementIdentityError("Test executable changed size while observing its disk identity")
                }
                record["on_disk_size"] = data.count
                record["on_disk_sha256"] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                let observedDiskUUID = try data.withUnsafeBytes { try placementMachOUUID($0) }
                diskUUID = observedDiskUUID
                record["on_disk_lc_uuid"] = observedDiskUUID
            } catch {
                errors.append("disk: " + error.localizedDescription)
            }
            let count = _dyld_image_count()
            record["dyld_image_count_before"] = count
            if count > 4096 {
                errors.append("Loaded image count exceeds the diagnostic bound")
            } else {
                for index in 0..<count {
                    guard let name = _dyld_get_image_name(index) else { continue }
                    let path = String(cString: name)
                    guard URL(fileURLWithPath: path).lastPathComponent == executable.lastPathComponent else { continue }
                    let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
                    var image: [String: Any] = [
                        "index": index, "path": path, "canonical_path": canonical,
                        "matches_bundle_executable": canonical == canonicalPath
                    ]
                    // Inspect only this test bundle's header. Other matching
                    // basenames are listed as ambiguity; their memory is not read.
                    if canonical == canonicalPath, let header = _dyld_get_image_header(index) {
                        do {
                            guard header.pointee.magic == UInt32(MH_MAGIC_64),
                                  header.pointee.sizeofcmds <= 4 * 1024 * 1024 else {
                                throw placementIdentityError("Unsupported or oversized loaded Mach-O header")
                            }
                            let byteCount = MemoryLayout<mach_header_64>.size + Int(header.pointee.sizeofcmds)
                            let bytes = UnsafeRawBufferPointer(start: UnsafeRawPointer(header), count: byteCount)
                            let uuid = try placementMachOUUID(bytes)
                            image["loaded_lc_uuid"] = uuid
                            matchingUUIDs.append(uuid)
                        } catch {
                            image["loaded_uuid_error"] = error.localizedDescription
                            errors.append("loaded: " + error.localizedDescription)
                        }
                    }
                    loadedImages.append(image)
                }
            }
            record["dyld_image_count_after"] = _dyld_image_count()
            if loadedImages.count != 1 || matchingUUIDs.count != 1 {
                errors.append("Expected exactly one loaded test image with the bundle's executable path and UUID")
            }
            if let diskUUID, matchingUUIDs.count == 1, matchingUUIDs[0] != diskUUID {
                errors.append("Loaded LC_UUID differs from the executable currently on disk")
            }
        } else {
            errors.append("Bundle has no executable URL")
        }
        record["loaded_images_with_test_executable_basename"] = loadedImages
        record["errors"] = errors
        record["identity_observation_valid"] = errors.isEmpty
        // A successful identity guard is not a UI acceptance result. Preserve
        // both representations before any assertion can terminate the scenario.
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            print("SETOS_PLACEMENT_UI_IDENTITY " + json)
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "SETOS_PLACEMENT_UI_IDENTITY-" + locale
            attachment.lifetime = .keepAlways
            add(attachment)
        } else {
            print("SETOS_PLACEMENT_UI_IDENTITY {\"serialization_failed\":true}")
            return false
        }
        return errors.isEmpty
    }

    private func placementMachOUUID(_ bytes: UnsafeRawBufferPointer) throws -> String {
        let headerSize = MemoryLayout<mach_header_64>.size
        guard bytes.count >= headerSize else { throw placementIdentityError("Truncated Mach-O header") }
        let header = bytes.loadUnaligned(as: mach_header_64.self)
        guard header.magic == UInt32(MH_MAGIC_64), header.ncmds > 0, header.ncmds <= 4096,
              header.sizeofcmds <= 4 * 1024 * 1024 else {
            throw placementIdentityError("Only a bounded native 64-bit Mach-O image is supported by this diagnostic")
        }
        let end = headerSize + Int(header.sizeofcmds)
        guard end <= bytes.count else { throw placementIdentityError("Truncated Mach-O load commands") }
        var offset = headerSize
        var uuid: String?
        for _ in 0..<header.ncmds {
            guard offset <= end - MemoryLayout<load_command>.size else {
                throw placementIdentityError("Load command header exceeds its declared region")
            }
            let command = bytes.loadUnaligned(fromByteOffset: offset, as: load_command.self)
            let size = Int(command.cmdsize)
            guard size >= MemoryLayout<load_command>.size, size % 8 == 0, size <= end - offset else {
                throw placementIdentityError("Invalid load command size")
            }
            if command.cmd == UInt32(LC_UUID) {
                guard size == MemoryLayout<uuid_command>.size, uuid == nil else {
                    throw placementIdentityError("Invalid or duplicate LC_UUID")
                }
                let command = bytes.loadUnaligned(fromByteOffset: offset, as: uuid_command.self)
                uuid = UUID(uuid: command.uuid).uuidString.lowercased()
            }
            offset += size
        }
        guard let uuid else { throw placementIdentityError("LC_UUID is missing") }
        return uuid
    }

    private func placementIdentityError(_ message: String) -> NSError {
        NSError(domain: "SETOSPlacementRuntimeIdentity", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func revealPlacementImage(in app: XCUIApplication, scroll: XCUIElement) -> CGRect {
        let image = app.images["camera_placement_image"]
        XCTAssertTrue(image.waitForExistence(timeout: 3))
        func fittedImage() -> CGRect {
            let frame = image.frame
            let side = min(frame.width, frame.height)
            return CGRect(x: frame.midX - side / 2, y: frame.midY - side / 2, width: side, height: side)
        }
        func requiredDragArea() -> CGRect {
            let fit = fittedImage()
            return CGRect(x: fit.minX + fit.width * 0.15, y: fit.minY + fit.height * 0.6,
                          width: fit.width * 0.3, height: fit.height * 0.18).insetBy(dx: -2, dy: -2)
        }
        revealPlacementRect(in: scroll, app: app, purpose: "image-drag-area", rect: requiredDragArea)
        XCTAssertTrue(scroll.frame.intersection(app.windows.firstMatch.frame).contains(requiredDragArea()),
                      "The real test gesture must stay inside the visible accepted image")
        return fittedImage()
    }

    private func revealPlacementControl(_ control: XCUIElement, in scroll: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(control.exists)
        revealPlacementRect(in: scroll, app: app, purpose: control.identifier) { control.frame }
        XCTAssertTrue(control.isHittable)
    }

    private func revealPlacementRect(
        in scroll: XCUIElement, app: XCUIApplication, purpose: String, rect: () -> CGRect
    ) {
        var observations: [String] = []
        func visibleRect() -> CGRect {
            scroll.frame.intersection(app.windows.firstMatch.frame).insetBy(dx: 2, dy: 4)
        }
        func fits() -> Bool {
            let target = rect()
            return target.width > 0 && target.height > 0 && visibleRect().contains(target)
        }
        func persistObservations() {
            observations.append("final target=\(rect()); visible=\(visibleRect()); fits=\(fits())")
            let attachment = XCTAttachment(string: observations.joined(separator: "\n"))
            attachment.name = "placement-scroll-observations-" + purpose
            attachment.lifetime = .keepAlways
            add(attachment)
            if !fits() {
                attachCloudConsentHierarchy(app, named: "placement-scroll-failure-" + purpose)
                attachScreenshot(app, named: "placement-scroll-failure-" + purpose)
            }
        }
        for step in 0..<12 {
            if fits() {
                persistObservations()
                return
            }
            let visible = visibleRect()
            let target = rect()
            guard visible.width > 0, visible.height > 0, target.width > 0, target.height > 0 else {
                persistObservations()
                XCTFail("The editor and target must have real nonempty bounds")
                return
            }
            let displacement = visible.midY - target.midY
            observations.append("step=\(step); before target=\(target); visible=\(visible)")
            let gesture = scrollPlacementEditor(scroll, in: app, contentDisplacement: displacement)
            observations.append(gesture.description)
            guard gesture.performed else {
                persistObservations()
                XCTFail("Scrolling requires a measured free lane inside the viewport, clear of the image")
                return
            }
            observations.append("step=\(step); after target=\(rect())")
        }
        // XCTest can terminate this scenario at the assertion when
        // continueAfterFailure is false; defer is not reliable evidence storage.
        persistObservations()
        XCTAssertTrue(fits(), "The complete editor target must be reachable inside the real scroll viewport")
    }

    private func scrollPlacementEditor(
        _ scroll: XCUIElement, in app: XCUIApplication, contentDisplacement: CGFloat
    ) -> (performed: Bool, description: String) {
        let visible = scroll.frame.intersection(app.windows.firstMatch.frame)
        // The image's accessibility frame follows its restricted drawable hit
        // shape. Obtain the content width independently from the actual fixture
        // region button, which shares the full editor content width.
        let imageFrame = app.images["camera_placement_image"].frame
        let content = app.buttons["camera_placement_region_0"]
        guard content.exists else {
            return (false, "The fixture's full-width region control is missing")
        }
        let contentFrame = content.frame
        guard contentFrame.width > 0, imageFrame.width > 0, imageFrame.height > 0,
              [contentFrame.minX, contentFrame.maxX, imageFrame.minX, imageFrame.maxX,
               imageFrame.minY, imageFrame.maxY].allSatisfy(\.isFinite) else {
            return (false, "Invalid observed content=\(contentFrame); image=\(imageFrame)")
        }
        let left = max(contentFrame.minX, visible.minX)
        let right = min(contentFrame.maxX, visible.maxX)
        let leftLetterboxWidth = imageFrame.minX - left
        let rightLetterboxWidth = right - imageFrame.maxX
        let clearance: CGFloat = 20
        let scrollX: CGFloat
        if leftLetterboxWidth >= 2 * clearance {
            scrollX = (left + imageFrame.minX) / 2
        } else if rightLetterboxWidth >= 2 * clearance {
            scrollX = (imageFrame.maxX + right) / 2
        } else {
            scrollX = max(visible.minX + 3, min(contentFrame.minX - 8, visible.maxX - 3))
        }
        let distance = min(max(abs(contentDisplacement), 12), visible.height * 0.35)
        let signedDistance = contentDisplacement > 0 ? distance : -distance
        let start = CGPoint(x: scrollX, y: visible.midY - signedDistance / 2)
        let end = CGPoint(x: scrollX, y: visible.midY + signedDistance / 2)
        let horizontalClearance = max(imageFrame.minX - scrollX, scrollX - imageFrame.maxX)
        let description = "gesture start=\(start); end=\(end); content=\(contentFrame); image=\(imageFrame); clearance=\(horizontalClearance)"
        guard visible.contains(start), visible.contains(end), !imageFrame.contains(start),
              horizontalClearance >= clearance else {
            return (false, "Rejected " + description)
        }
        placementDrag(in: app,
                      from: start, to: end, controlledScroll: true)
        return (true, description)
    }

    private func placementDrag(
        in app: XCUIApplication, from start: CGPoint, to end: CGPoint, controlledScroll: Bool = false
    ) {
        let window = app.windows.firstMatch
        let origin = window.coordinate(withNormalizedOffset: .zero)
        let from = origin.withOffset(CGVector(dx: start.x - window.frame.minX, dy: start.y - window.frame.minY))
        let to = origin.withOffset(CGVector(dx: end.x - window.frame.minX, dy: end.y - window.frame.minY))
        if controlledScroll {
            // Hold at the observed destination to avoid a fling past the target.
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
        } else {
            from.press(forDuration: 0.05, thenDragTo: to)
        }
    }

    func testSceneControlRuntimeENLandscapeXXLReachesEveryIndependentAnswer() throws {
        try prepareSimulatorIPadFullScreenLayout()
        let app = launchSceneControl(locale: "en", orientation: .landscapeLeft, dynamicType: true)
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        assertSceneControlLandscape(in: app)
        let open = app.buttons["camera_scene_control_open"]
        XCTAssertTrue(open.waitForExistence(timeout: 6))
        XCTAssertTrue(open.isHittable)
        assertSceneControlPauseLayout(in: app)
        assertPauseReviewTextAndActionReachable(in: app, locale: "en")
        open.tap()
        let done = app.buttons["camera_scene_control_done"]
        XCTAssertTrue(done.waitForExistence(timeout: 4))
        assertSceneControlLandscape(in: app)
        XCTAssertTrue(done.isHittable)
        XCTAssertGreaterThanOrEqual(done.frame.height + coordinateRoundoff, 44)
        attachScreenshot(app, named: "scene-control-runtime-en-landscape-xxl-top")
        selectSceneControl("objects", answer: "No", in: app)
        selectSceneControl("participants", answer: "Yes", in: app)
        selectSceneControl("lighting", answer: "Yes", in: app)
        attachScreenshot(app, named: "scene-control-runtime-en-landscape-xxl-bottom")
        done.tap()
        assertSceneControlState(in: app, objects: "forbidden", participants: "allowed", lighting: "allowed", physical: false)
        open.tap()
        let reset = app.buttons["camera_scene_control_reset"]
        for _ in 0..<8 {
            if reset.isHittable { break }
            app.scrollViews["camera_scene_control_scroll"].swipeUp()
        }
        XCTAssertTrue(reset.isHittable)
        XCTAssertGreaterThanOrEqual(reset.frame.height + coordinateRoundoff, 44)
        XCTAssertGreaterThanOrEqual(reset.frame.minX, app.windows.firstMatch.frame.minX)
        XCTAssertLessThanOrEqual(reset.frame.maxX, app.windows.firstMatch.frame.maxX)
        reset.tap()
        done.tap()
        assertSceneControlState(in: app, objects: "unknown", participants: "unknown", lighting: "unknown", physical: false)
    }

    private func selectSceneControl(_ category: String, answer: String, in app: XCUIApplication) {
        let picker = app.buttons["camera_scene_control_" + category]
        for _ in 0..<8 {
            if picker.isHittable { break }
            app.scrollViews["camera_scene_control_scroll"].swipeUp()
        }
        XCTAssertTrue(picker.isHittable, "Every category must remain reachable in the production sheet")
        XCTAssertGreaterThanOrEqual(picker.frame.height + coordinateRoundoff, 44)
        XCTAssertGreaterThanOrEqual(picker.frame.minX, app.windows.firstMatch.frame.minX)
        XCTAssertLessThanOrEqual(picker.frame.maxX, app.windows.firstMatch.frame.maxX)
        picker.tap()
        let option = app.buttons.matching(NSPredicate(format: "label == %@", answer)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()
    }

    private func assertSceneControlLandscape(in app: XCUIApplication) {
        let landscape = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let viewport = app.windows.firstMatch.frame
                return viewport.width > viewport.height
            }, object: app
        )
        let result = XCTWaiter.wait(for: [landscape], timeout: 5)
        attachCameraWindowGeometry(app, named: "scene-control-landscape-window")
        XCTAssertEqual(result, .completed,
                       "A landscape UI acceptance requires an actual landscape viewport")
    }

    private func assertSceneControlPauseLayout(in app: XCUIApplication) {
        let viewport = app.windows.firstMatch.frame
        let footer = app.buttons["camera_scene_control_open"]
        let review = app.scrollViews["camera_coach_review_scroll"]
        XCTAssertTrue(review.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(review.frame.height, 0)
        XCTAssertGreaterThanOrEqual(review.frame.minX, viewport.minX)
        XCTAssertLessThanOrEqual(review.frame.maxX, viewport.maxX)
        XCTAssertLessThanOrEqual(review.frame.maxY, footer.frame.minY + 0.5,
                                 "Review content must scroll above the distinct scene-control footer")
        XCTAssertGreaterThanOrEqual(footer.frame.minX, viewport.minX)
        XCTAssertLessThanOrEqual(footer.frame.maxX, viewport.maxX)
        XCTAssertGreaterThanOrEqual(footer.frame.height + coordinateRoundoff, 44)
        let resume = app.buttons["camera_coach_pause"]
        XCTAssertTrue(resume.isHittable)
        XCTAssertLessThanOrEqual(resume.frame.maxX, viewport.maxX)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "presentation")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "x=")).firstMatch.exists)
        attachScreenshot(app, named: "scene-control-runtime-bounded-pause-\(viewport.width > viewport.height ? "landscape" : "portrait")")
    }

    private func assertPauseReviewTextAndActionReachable(in app: XCUIApplication, locale: String) {
        let review = app.scrollViews["camera_coach_review_scroll"]
        // Product decision (owner-delegated 2026-09-27, CAM-002 copy-drift §19 п.11):
        // stale oracle, not a presentation regression. The pre-5c15f3a2 literal
        // ("Попробуй другую точку съёмки…" / "Try another camera position…") exists
        // only in this test; commit 5c15f3a2 ("fix(camera): name the phone in the
        // change-angle copy") deliberately renamed set.camera.corrective.change_angle
        // and set.trace.action.change_angle so both locales name the phone (the
        // CameraCoachLocalizationAddresseeTests addressee gate), matching the
        // planner's own wording. The oracle therefore follows the shipped copy.
        let expectedText = locale == "ru"
            ? "Сместись с телефоном к другой точке съёмки, сохраняя главный объект в кадре"
            : "Move with the phone to another camera position while keeping the main subject in frame"
        // The alternatives section repeats the advice. Inspect the primary
        // occurrence in reading order, not a different copy farther below.
        let advice = review.staticTexts.matching(NSPredicate(format: "label == %@", expectedText)).firstMatch
        XCTAssertTrue(advice.waitForExistence(timeout: 3))
        XCTAssertEqual(advice.label, expectedText)
        revealPauseReviewElement(advice, in: review, app: app, name: "primary-advice-\(locale)")
        let action = review.buttons["camera_coach_pause_action"]
        revealPauseReviewElement(action, in: review, app: app, name: "primary-action-\(locale)")
        XCTAssertTrue(action.isHittable)
        XCTAssertGreaterThanOrEqual(action.frame.height + coordinateRoundoff, 44)
        XCTAssertGreaterThanOrEqual(action.frame.width + coordinateRoundoff, 44)
        // The subsequent scenario still opens scene control from the fixed
        // footer; reaching review content must not obscure that entry point.
        XCTAssertTrue(app.buttons["camera_scene_control_open"].isHittable)
    }

    private func revealPauseReviewElement(
        _ element: XCUIElement, in review: XCUIElement, app: XCUIApplication, name: String
    ) {
        var observations: [String] = []
        var stopReason = "Reached the 16-gesture limit"
        var previousTravel: (direction: CGFloat, unconsumed: CGFloat, target: CGRect, visible: CGRect)?
        func valid(_ frame: CGRect) -> Bool {
            !frame.isNull && frame.width > 0 && frame.height > 0
                && [frame.minX, frame.maxX, frame.minY, frame.maxY,
                    frame.width, frame.height].allSatisfy(\.isFinite)
        }
        func fits(_ frame: CGRect, in visible: CGRect) -> Bool {
            valid(frame) && valid(visible)
                && frame.minX + coordinateRoundoff >= visible.minX
                && frame.maxX <= visible.maxX + coordinateRoundoff
                && frame.minY + coordinateRoundoff >= visible.minY
                && frame.maxY <= visible.maxY + coordinateRoundoff
        }
        func sameBounds(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
            valid(lhs) && valid(rhs)
                && zip([lhs.minX, lhs.minY, lhs.width, lhs.height],
                       [rhs.minX, rhs.minY, rhs.width, rhs.height])
                    .allSatisfy { abs($0.0 - $0.1) <= coordinateRoundoff }
        }
        for step in 0..<16 {
            guard element.exists, review.exists, app.windows.firstMatch.exists else {
                stopReason = "Target, review, or window is missing"
                break
            }
            let target = element.frame
            let reviewFrame = review.frame
            let windowFrame = app.windows.firstMatch.frame
            guard valid(target), valid(reviewFrame), valid(windowFrame) else {
                observations.append("step=\(step); invalid target=\(target); review=\(reviewFrame); window=\(windowFrame)")
                stopReason = "Nonfinite or empty observed bounds"
                break
            }
            let visible = reviewFrame.intersection(windowFrame)
            observations.append("step=\(step); before target=\(target); visible=\(visible)")
            if fits(target, in: visible) { stopReason = "Fully visible"; break }
            guard valid(visible), target.height <= visible.height + 2 * coordinateRoundoff,
                  target.minX + coordinateRoundoff >= visible.minX,
                  target.maxX <= visible.maxX + coordinateRoundoff else {
                stopReason = "Vertical scrolling cannot fit these observed bounds"
                break
            }
            // Center the observed target, capping long travel. Compensate only
            // travel actually unconsumed by the preceding same-direction pan.
            let delta = visible.midY - target.midY
            guard delta.isFinite, abs(delta) > coordinateRoundoff else {
                stopReason = "No nonzero measured scroll is available; do not tap"
                break
            }
            let direction: CGFloat = delta > 0 ? 1 : -1
            let compensation: CGFloat
            if let previousTravel, previousTravel.direction == direction,
               sameBounds(previousTravel.target, target), sameBounds(previousTravel.visible, visible) {
                compensation = previousTravel.unconsumed
            } else {
                compensation = 0
            }
            previousTravel = nil
            // No blind minimum or cross-direction calibration. A first short
            // unrecognized gesture still fails with evidence, without tapping.
            let requestedDistance = min(abs(delta) + compensation, visible.height * 0.35)
            let interiorMinY = visible.minY + 4
            let interiorMaxY = visible.maxY - 4
            guard interiorMinY < interiorMaxY else {
                stopReason = "Viewport has no interior drag segment"
                break
            }
            let buttons = review.buttons.allElementsBoundByIndex.filter { $0.exists }.map { $0.frame }
            guard buttons.allSatisfy(valid) else {
                stopReason = "A review button has invalid bounds; do not touch an unknown control"
                break
            }
            // Stay in the observed content span, never the window's empty side
            // margin. Button edges supply starts; shorten travel when necessary
            // to keep the entire gesture inside the viewport.
            let blocked = buttons.map { $0.insetBy(dx: -8, dy: -8) }
            let xs = [target.midX, target.minX + target.width * 0.25,
                      target.minX + target.width * 0.75]
            var gesture: (start: CGPoint, end: CGPoint, distance: CGFloat)?
            for x in xs {
                var ys = [visible.midY - direction * requestedDistance / 2,
                          interiorMinY, interiorMaxY]
                for button in blocked where x >= button.minX && x <= button.maxX {
                    // One point beyond the exclusion edge avoids rounding a
                    // synthetic touch back onto that edge; it is not a pan minimum.
                    ys.append(button.minY - 1)
                    ys.append(button.maxY + 1)
                }
                for y in ys {
                    guard y >= interiorMinY, y <= interiorMaxY else { continue }
                    let start = CGPoint(x: x, y: y)
                    let available = direction > 0 ? interiorMaxY - y : y - interiorMinY
                    let clippedDistance = min(requestedDistance, available)
                    guard clippedDistance > coordinateRoundoff else { continue }
                    let end = CGPoint(x: x, y: y + direction * clippedDistance)
                    if visible.contains(start), visible.contains(end),
                       !blocked.contains(where: { $0.contains(start) }) {
                        let actualDistance = abs(end.y - start.y)
                        if actualDistance > (gesture?.distance ?? 0) + coordinateRoundoff {
                            // Largest safe progress wins; iteration order keeps
                            // content-center X when distances are tied.
                            gesture = (start, end, actualDistance)
                        }
                    }
                }
            }
            guard let gesture else {
                stopReason = "No measured start clear of review buttons is available"
                break
            }
            let distance = gesture.distance
            let displacement = gesture.end.y - gesture.start.y
            observations.append("step=\(step); delta=\(delta); compensation=\(compensation); requestedDistance=\(requestedDistance); displacement=\(displacement); start=\(gesture.start); end=\(gesture.end); buttons=\(buttons); velocity=slow; hold=0.2")
            placementDrag(in: app, from: gesture.start, to: gesture.end, controlledScroll: true)
            guard element.exists, review.exists, app.windows.firstMatch.exists else {
                stopReason = "Target, review, or window disappeared after the gesture"
                break
            }
            let after = element.frame
            let afterVisible = review.frame.intersection(app.windows.firstMatch.frame)
            observations.append("step=\(step); after target=\(after); visible=\(afterVisible)")
            if fits(after, in: afterVisible) { stopReason = "Fully visible"; break }
            let consumed = direction * ((after.midY - afterVisible.midY) - (target.midY - visible.midY))
            if valid(after), sameBounds(visible, afterVisible),
               abs(after.minX - target.minX) <= coordinateRoundoff,
               abs(after.width - target.width) <= coordinateRoundoff,
               abs(after.height - target.height) <= coordinateRoundoff,
               consumed > coordinateRoundoff, consumed <= distance + coordinateRoundoff {
                let unconsumed = min(max(0, distance - consumed), visible.height * 0.35)
                previousTravel = (direction, unconsumed, after, afterVisible)
                observations.append("step=\(step); consumed=\(consumed); calibratedUnconsumed=\(unconsumed)")
            } else {
                observations.append("step=\(step); consumed=\(consumed); calibrationRejected")
            }
            if valid(after), valid(afterVisible),
               abs((after.midY - afterVisible.midY) - (target.midY - visible.midY)) <= coordinateRoundoff {
                stopReason = "Gesture made no observed progress"
                break
            }
        }
        let finalFrame = element.exists ? element.frame : .zero
        let finalVisible = review.exists && app.windows.firstMatch.exists
            ? review.frame.intersection(app.windows.firstMatch.frame) : .null
        let fullyVisible = element.exists && fits(finalFrame, in: finalVisible)
        observations.append("final target=\(finalFrame); visible=\(finalVisible); fits=\(fullyVisible); stop=\(stopReason)")
        let attachment = XCTAttachment(string: observations.joined(separator: "\n"))
        attachment.name = "pause-review-scroll-observations-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
        // Persist before the assertion: continueAfterFailure=false can prevent defer.
        attachCloudConsentHierarchy(app, named: "pause-review-\(name)-hierarchy")
        attachScreenshot(app, named: "pause-review-\(name)-fully-visible")
        XCTAssertTrue(fullyVisible, "The entire element must be visible inside the real bounded review viewport: \(stopReason)")
    }

    private func assertSceneControlState(in app: XCUIApplication, objects: String, participants: String,
                                         lighting: String, physical: Bool) {
        let probe = app.staticTexts["camera_scene_control_fixture_state"]
        XCTAssertTrue(probe.waitForExistence(timeout: 4))
        let expected = "objects=\(objects);participants=\(participants);lighting=\(lighting);physicalObjectAdvice=\(physical);verification=none"
        let observed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: probe)
        XCTAssertEqual(XCTWaiter.wait(for: [observed], timeout: 4), .completed,
                       "The UI gesture must reach the actual ViewModel associated success payload")
    }

    private func launchSceneControl(locale: String, orientation: UIDeviceOrientation,
                                     dynamicType: Bool = false, activePlacement: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchEnvironment["SHAFIN_UI_TESTING"] = "1"
        app.launchEnvironment["SETOS_SCENE_BASE_URL"] = "http://camera-scene-control-fixture.invalid"
        if activePlacement { app.launchEnvironment["SHAFIN_UI_TEST_IMAGE_PLACEMENT_ACTIVE"] = "1" }
        app.launchArguments = ["-SHAFIN_CAMERA_PRODUCTION_FIXTURE", "camera.scene-control",
                               "-SHAFIN_SET_LOCALE", locale, "-SHAFIN_SET_REDUCE_MOTION", "1"]
        if orientation.isLandscape {
            // Qualifies real landscape layout through UIKit scene geometry;
            // simulator sensor injection remains independently unqualified.
            app.launchArguments += ["-SHAFIN_SET_INTERFACE_GEOMETRY", "landscape"]
        }
        if dynamicType { app.launchArguments += ["-SHAFIN_SET_DYNAMIC_TYPE", "xxl"] }
        app.launch()
        // Apply the requested rotation after the real fixture window exists;
        // the previous app's orientation is not evidence of this viewport.
        XCUIDevice.shared.orientation = orientation
        return app
    }

    private func launchCloudConsent(locale: String, orientation: UIDeviceOrientation) -> XCUIApplication {
        // Establish orientation in the running host before presenting the sheet.
        // A pre-launch device orientation alone does not prove its window rotated.
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["SHAFIN_UI_TESTING"] = "1"
        // AppDelegate runs before the fixture route. A present but invalid
        // endpoint wins over bundle deployment config and fails validation
        // before any client/token provider or shared parser is constructed.
        app.launchEnvironment["SETOS_SCENE_BASE_URL"] = "http://camera-consent-fixture.invalid"
        app.launchArguments = [
            "-SHAFIN_CAMERA_CLOUD_CONSENT_FIXTURE",
            "-SHAFIN_SET_LOCALE", locale,
            "-SHAFIN_SET_REDUCE_MOTION", "1",
            "-SHAFIN_SET_DYNAMIC_TYPE", "xxl"
        ]
        if orientation.isLandscape {
            app.launchArguments += ["-SHAFIN_SET_INTERFACE_GEOMETRY", "landscape"]
        }
        app.launch()
        let open = app.buttons["camera_cloud_fixture_open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = orientation
        let landscape = orientation == .landscapeLeft || orientation == .landscapeRight
        let windowHasRequestedOrientation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let frame = app.windows.firstMatch.frame
                return frame.width > 0 && frame.height > 0
                    && (landscape ? frame.width > frame.height : frame.height > frame.width)
            },
            object: app
        )
        let result = XCTWaiter.wait(for: [windowHasRequestedOrientation], timeout: 5)
        attachCameraWindowGeometry(app, named: "cloud-consent-\(locale)-window")
        XCTAssertEqual(result, .completed,
                       "The consent test must exercise the requested actual window orientation")
        assertCloudConsentActionVisible(open, in: app)
        open.tap()
        return app
    }

    private func assertCloudConsentActionVisible(
        _ action: XCUIElement, in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(action.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertTrue(action.isHittable, file: file, line: line)
        let frame = action.frame
        let viewport = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(frame.width + coordinateRoundoff, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.height + coordinateRoundoff, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minX + coordinateRoundoff, viewport.minX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY + coordinateRoundoff, viewport.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, viewport.maxX + coordinateRoundoff, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, viewport.maxY + coordinateRoundoff, file: file, line: line)
    }

    private func attachCloudConsentHierarchy(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachCameraWindowGeometry(_ app: XCUIApplication, named name: String) {
        let probe = app.otherElements["camera_coach_lifecycle_diagnostic"]
        let ownerState = probe.exists ? String(describing: probe.value) : "diagnostic-probe-missing"
        let diagnostic = "XCUI window=\(app.windows.firstMatch.frame)\n"
            + "XCUI app=\(app.frame)\n"
            + "requestedDeviceOrientation=\(XCUIDevice.shared.orientation.rawValue)\n"
            + "explicitFixtureGeometry=\(app.launchArguments.contains("-SHAFIN_SET_INTERFACE_GEOMETRY"))\n"
            + "automaticSensorRotationQualified=false\n"
            + "UIKit owner snapshot=\(ownerState)"
        let attachment = XCTAttachment(string: diagnostic)
        attachment.name = name + "-owner-state"
        attachment.lifetime = .keepAlways
        add(attachment)
        attachCloudConsentHierarchy(app, named: name + "-hierarchy")
        attachScreenshot(app, named: name + "-screen")
    }

    private func assertVisibleTextFitsViewport(
        _ label: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let text = app.staticTexts[label].firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 4), file: file, line: line)
        let viewport = app.frame
        XCTAssertGreaterThan(text.frame.width, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(text.frame.minX, viewport.minX, file: file, line: line)
        XCTAssertLessThanOrEqual(text.frame.maxX, viewport.maxX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(text.frame.minY, viewport.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(text.frame.maxY, viewport.maxY, file: file, line: line)
    }

    private func launch(
        fixture: String,
        locale: String,
        orientation: UIDeviceOrientation,
        reduceMotion: Bool = false,
        dynamicType: Bool = false,
        runtimeSignal: String? = nil
    ) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = [
            "-SHAFIN_CAMERA_PRODUCTION_FIXTURE", fixture,
            "-SHAFIN_SET_LOCALE", locale
        ]
        if reduceMotion {
            app.launchArguments += ["-SHAFIN_SET_REDUCE_MOTION", "1"]
        }
        if dynamicType {
            app.launchArguments += ["-SHAFIN_SET_DYNAMIC_TYPE", "xxl"]
        }
        if let runtimeSignal {
            app.launchArguments += ["-SHAFIN_CAMERA_RUNTIME_SIGNAL", runtimeSignal]
        }
        app.launch()
        return app
    }

    private func assertRoot(_ fixture: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            app.otherElements[fixture].waitForExistence(timeout: 4),
            "Missing deterministic production fixture \(fixture)",
            file: file,
            line: line
        )
    }

    private func assertStableCameraIdentifiers(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(
            app.buttons["camera_coach_close"].exists,
            "Camera Coach is the CommercialShell root; a close control would be nonfunctional.",
            file: file,
            line: line
        )
        XCTAssertTrue(app.buttons["camera_coach_pause"].exists, file: file, line: line)
        XCTAssertTrue(app.otherElements["camera_coach_live_surface"].exists, file: file, line: line)
    }

    private func assertSemanticFixtureState(
        _ fixtureID: String,
        expectedState: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let matchingElements = app
            .descendants(matching: .any)
            .matching(identifier: fixtureID)
        XCTAssertTrue(
            matchingElements.firstMatch.waitForExistence(timeout: 3),
            "Missing legacy command-band surface for \(fixtureID)",
            file: file,
            line: line
        )
        let matchingValues = (0..<matchingElements.count).compactMap { index in
            matchingElements.element(boundBy: index).value as? String
        }
        XCTAssertEqual(
            matchingValues.contains(expectedState),
            true,
            "Fixture \(fixtureID) must expose semantic state \(expectedState) via accessibilityValue",
            file: file,
            line: line
        )
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "v26-package2-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

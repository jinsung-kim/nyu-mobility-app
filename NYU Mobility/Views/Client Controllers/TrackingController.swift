//
//  TrackingController.swift
//  NYU Mobility
//
//  Created by Jin Kim on 5/29/20.
//  Copyright © 2020 Jin Kim. All rights reserved.
//

import UIKit
import CoreData // Local storage (user saved locations)
import CoreMotion // Used to track user movement
import CoreLocation // Used to access coordinate data
import AVFoundation // Used to play sounds
import MessageUI // Used to send emails

class TrackingController: UIViewController, CLLocationManagerDelegate, MFMailComposeViewControllerDelegate {
    
    @IBOutlet var viewer: UIView!
    @IBOutlet weak var circleView: UIView!
    
    // Button used to change states
    @IBOutlet weak var trackingButton: UIButton!
    
    // Creating a new LocationManager Object
    private let locationManager: CLLocationManager = CLLocationManager()
    private var locationArray: [String: [Double]] = ["long": [], "lat": []]
    
    // Pedometer object - used to trace each step
    private let activityManager: CMMotionActivityManager = CMMotionActivityManager()
    private let pedometer: CMPedometer = CMPedometer()
    
    // Gyro Sensor
    private let motionManager: CMMotionManager = CMMotionManager()
    // Used to store all x, y, z values
    private var gyroDict: [String: [Double]] = ["x": [], "y": [], "z": []]
    
    // Pace trackers
    private var currPace: Double = 0.0
    private var avgPace: Double = 0.0
    private var currCad: Double = 0.0
    
    // Responsive button sounds
    var player: AVAudioPlayer?
    
    // Triggering the button's three states
    private var buttonState: Int = 0
    
    // Used to track pedometer when saving data
    var steps: Int32 = 0
    var maxSteps: Int32 = 0
    var distance: Int32 = 0 // In meters
    var maxDistance: Int32 = 0
    
    // Used for creating the JSON
    var points: [Point] = []
    var coords: [CLLocationCoordinate2D] = []
    
    // Start Time
    var startTime: Date = Date()
    
    // Local Storage
    var userLocations: [NSManagedObject] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Screen will not go to sleep with this line below
        UIApplication.shared.isIdleTimerDisabled = true
        
        navigationItem.setHidesBackButton(true, animated: false)
        createCircleView()
        settingsButton() // The right side button
        getLocationPermission() // Permission to track
        enableDoubleTap() // Double tap feature
    }
    
    func createCircleView() {
        circleView.layer.cornerRadius = 120 // half the width / height
        circleView.backgroundColor = Colors.nyuPurple
    }
    
    // Used to send over data to MapView Controller to read out results
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.destination is MapViewController {
            let vc = segue.destination as? MapViewController
            vc?.steps = maxSteps
            vc?.coords = coords
            vc?.distance = maxDistance
        } else {
            let vc = segue.destination as? ShareSessionController
            vc?.points = points
        }
    }
    
    // Upper right item from the tracking controller that goes to the settings
    func settingsButton() {
        let settingsButton = UIBarButtonItem()
        settingsButton.title = "Settings"
        settingsButton.action = #selector(settingsTap)
        settingsButton.target = self
        navigationItem.rightBarButtonItem = settingsButton
    }
    
    // Double tap pauses and resumes given the previous state
    func enableDoubleTap() {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(TrackingController.labelTapped(recognizer: )))
        tapGestureRecognizer.numberOfTapsRequired = 2
        
        trackingButton.isUserInteractionEnabled = true
        trackingButton.addGestureRecognizer(tapGestureRecognizer)
    }
    
    // Redirects to settings page
    @objc func settingsTap() {
        playSound("settings")
        performSegue(withIdentifier: "SettingsSegue", sender: self)
    }
    
    // Goes together with enableDoubleTap
    @objc func labelTapped(recognizer: UITapGestureRecognizer) {
        if (buttonState == 1) {
            playSound("pause")
            trackingButton.setTitle("Resume", for: .normal)
            buttonState = 3
            toggleButton(trackingButton)
        } else {
            playSound("resume")
            trackingButton.setTitle("Pause", for: .normal)
            buttonState = 4
            toggleButton(trackingButton)
        }
    }
    /**
        Takes the date and returns it in yyyy-MM-dd hh:mm:ss form
        Used to store within CoreData + Firebase
     - Parameters:
        - date: Date that needs to be converted; by default, the time the session was recorded

     - Returns: String containing the date in the new format
    */
    func dateToString(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd hh:mm:ss"
        let dateString = formatter.string(from: date)
        return dateString
    }
    
    /**
        Turns all of the points generated throughout the session and turns it into a JSON file
       - Returns: String containing the JSON file (after being serialized)
    */
    func generateJSON() -> String {
        let dicArray = points.map { $0.convertToDictionary() }
        if let data = try? JSONSerialization.data(withJSONObject: dicArray, options: .prettyPrinted) {
            let str = String(bytes: data, encoding: .utf8)
            return str!
        }
        return "There was an error generating the JSON file"
    }
    
    /**
        Used to toggle into the next state of the button and tracking process
        Refers to the button state used globally
            0: Has not been turned on
            1: Currently tracking
            2: Done tracking
            3: Pause
            4: Resume
        - Parameters:
            - sender: The tracking button
     */
    @IBAction func toggleButton(_ sender: UIButton) {
        switch(self.buttonState) {
        case 0:
            startTracking()
            playSound("start")
            sender.setTitle("Stop", for: .normal)
            buttonState = 1
        case 1:
            stopTracking()
            playSound("stop")
            sender.setTitle("Reset", for: .normal)
            buttonState = 2
        case 2:
            // Redirects to the share button
            self.performSegue(withIdentifier: "ShareSession", sender: self)
            clearData()
            playSound("reset")
            sender.setTitle("Start", for: .normal)
            buttonState = 0
        case 3:
            stopTracking()
            buttonState = 0
        case 4:
            startTracking()
            playSound("resume")
            sender.setTitle("Stop", for: .normal)
            buttonState = 1
        default: // Should never happen
            print("Unexpected case: \(self.buttonState)")
        }
    }
    
    func saveSession() {
        let json: String = generateJSON()
        let code: String = UserDefaults.standard.string(forKey: "code")!
        let mode: String = "client"
        let name: String = UserDefaults.standard.string(forKey: "name")!
        
        DatabaseManager.shared.insertClientSession(code: code, json: json, clientName: name,
                                                   startTime: dateToString(startTime), mode: mode,
                                                   videoURL: "", completion: { success in
            if (!success) {
                print("Failed to save to database")
            }
        })
    }
    
    // Should only do this once
    func getLocationPermission() {
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization()
    }
    
    // Continuously gets the location of the user
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for _ in locations { // _ -> currentLocation
            if let location: CLLocation = locationManager.location {
                // Coordinate object
                let coordinate: CLLocationCoordinate2D = location.coordinate
                coords.append(coordinate)
                // ... proceed with the location and coordinates
                if (locationArray["lat"] == nil) {
                    locationArray["lat"] = [coordinate.latitude]
                    locationArray["long"] = [coordinate.longitude]
                } else {
                    locationArray["lat"]!.append(coordinate.latitude)
                    locationArray["long"]!.append(coordinate.longitude)
                }
            }
            // Looks like this when debugged (city bike ride):
            // (Function): <+37.33144466,-122.03075535> +/- 30.00m
            // (speed 6.01 mps / course 180.98) @ 3/13/20, 8:55:48 PM Pacific Daylight Time
        }
    }
    
    /**
        Starts the gyroscope tracking, GPS location tracking, and pedometer object
        Assumes that location permissions and motion permissions have already been granted
        Changes the color of the UIView to green (indicating that it is in go mode)
     */
    func startTracking() {
        locationManager.startUpdatingLocation()
        startTime = Date()
        startGyro()
        startUpdating()
        self.saveData(currTime: Date(), significant: true)
    }
    
    /**
        Stops tracking the gyroscope, GPS location, and pedometer object
        Assumes that the previously stated managers are running
     */
    func stopTracking() {
        locationManager.stopUpdatingLocation()
        stopUpdating()
        stopGyros()
        saveData(currTime: Date(), significant: true)
    }
    
    func stopUpdating() { pedometer.stopUpdates() }
    
    // Pedometer Functions
    
    func startUpdating() {
        if CMMotionActivityManager.isActivityAvailable() {
            startTrackingActivityType()
        }

        if CMPedometer.isStepCountingAvailable() {
            startCountingSteps()
        }
    }
    
    // Starts at 0 for all digits
    func startTrackingActivityType() {
        activityManager.startActivityUpdates(to: OperationQueue.main) {
            [weak self] (activity: CMMotionActivity?) in
            self?.steps = 0
            self?.distance = 0
            self?.maxSteps = 0
            self?.maxDistance = 0
        }
    }
    
    func startCountingSteps() {
        pedometer.startUpdates(from: Date()) {
          [weak self] pedometerData, error in
          guard let pedometerData = pedometerData, error == nil else { return }

            // Runs concurrently
            DispatchQueue.main.async {
                self?.saveData(currTime: Date(), significant: false)
                self?.distance = Int32(truncating: pedometerData.distance ?? 0)
                self?.steps = Int32(truncating: pedometerData.numberOfSteps)
                self?.avgPace = Double(truncating: pedometerData.averageActivePace ?? 0)
                self?.currPace = Double(truncating: pedometerData.currentPace ?? 0)
                self?.currCad = Double(truncating: pedometerData.currentCadence ?? 0)
            }
        }
    }
    
    /**
        Saves the given data into the stack, and clears out the gyroscope data to start taking values again
        - Parameters:
            - currTime: Date in which the data has been tracked
     */
    func saveData(currTime: Date, significant: Bool) {
        // JSON array implementation (See Point.swift for model)
        if (steps >= maxSteps) {
            maxSteps = steps
        }
        if (distance >= maxDistance) {
            maxDistance = distance
        }
        if (maxDistance != 0 || maxSteps != 0 || points.isEmpty || significant) {
            points.append(Point(dateToString(), maxSteps, maxDistance, avgPace,
                                currPace, currCad, locationArray, gyroDict))
            
            // Clear the gyroscope data after getting its string representation
            gyroDict.removeAll()
            locationArray.removeAll()
        }
    }
    
    func clearData() {
        points.removeAll()
        coords.removeAll()
    }
    
    // Gyroscope Functions
    
    // Starts the gyroscope once it is confirmed to be available
    func startGyro() {
        if motionManager.isGyroAvailable {
            // Set to update 5 times a second
            motionManager.gyroUpdateInterval = 0.2
            motionManager.startGyroUpdates(to: OperationQueue.current!) { (data, error) in
                if let gyroData = data {
                    if (self.gyroDict["x"] == nil) { // No entries for this point yet
                        self.gyroDict["x"] = [gyroData.rotationRate.x]
                        self.gyroDict["y"] = [gyroData.rotationRate.y]
                        self.gyroDict["z"] = [gyroData.rotationRate.z]
                    } else { // We know there are already values inserted
                        self.gyroDict["x"]!.append(gyroData.rotationRate.x)
                        self.gyroDict["y"]!.append(gyroData.rotationRate.y)
                        self.gyroDict["z"]!.append(gyroData.rotationRate.z)
                    }
                    // Ex (output):
                    // CMRotationRate(x: 0.6999756693840027, y: -1.379577398300171, z: -0.3633846044540405)
                }
            }
        }
    }
    
    // Stops the gyroscope (assuming that it is available)
    func stopGyros() { motionManager.stopGyroUpdates() }
    
    // Sound Functionality
    
    /**
        Plays a sound given the state of the button
        - Parameters:
            - fileName: The name of the file being executed (all within 'Sound' group)
     */
    func playSound(_ fileName: String) {
        if (getState()) {
            guard let url = Bundle.main.url(forResource: fileName, withExtension: "mp3") else { return }

            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)

                player = try AVAudioPlayer(contentsOf: url, fileTypeHint: AVFileType.mp3.rawValue)

                guard let player = player else { return }

                player.play()

            } catch let error {
                print("Unexpected Behavior: \(error.localizedDescription)")
            }
        }
    }
    
    // Gesture Functionality
    func getState() -> Bool {
        let defaults = UserDefaults.standard
        let gesture = defaults.bool(forKey: "state")
        return gesture
    }
    
}

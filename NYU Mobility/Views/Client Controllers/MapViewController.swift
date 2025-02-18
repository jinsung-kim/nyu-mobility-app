//
//  MapViewController.swift
//  NYU Mobility
//
//  Created by Jin Kim on 6/8/20.
//  Copyright © 2020 Jin Kim. All rights reserved.
//

import UIKit
import MapKit
import AVFoundation
import CoreData

class MapViewController: UIViewController, MKMapViewDelegate {
    
    // Controller View Objects
    @IBOutlet weak var mapView: MKMapView!
    // Distance + Step Labels
    @IBOutlet weak var distanceLabel: UILabel!
    @IBOutlet weak var stepsLabel: UILabel!
    
    var player: AVAudioPlayer?
    
    // Used to track pedometer when saving data
    var steps: Int32 = 0
    var distance: Int32 = 0
    
    // Used for creating the JSON that will be manipulated to grab the coordinates
    var coords: [CLLocationCoordinate2D] = []
    
    var userLocations: [NSManagedObject] = []
    
    // All the map functions go here
    override func viewDidLoad() {
        super.viewDidLoad()
        mapView.isScrollEnabled = false
        loadData()
        addAnnotations()
        updateLabels()
        // Only voice results if voice gestures are activated
        voiceResults()
        generateLine()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        playSound("back")
        let overlays = mapView.overlays
        mapView.removeOverlays(overlays)
        mapView.delegate = nil
    }
    
    // Core Data
    
    func loadData() {
        guard let appDelegate =
            UIApplication.shared.delegate as? AppDelegate else {
            return
        }
        
        let managedContext =
            appDelegate.persistentContainer.viewContext
        
        let fetchRequest =
            NSFetchRequest<NSManagedObject>(entityName: "UserSaved")
        
        do {
            userLocations = try managedContext.fetch(fetchRequest)
        } catch let error as NSError {
            print("Could not fetch. \(error), \(error.userInfo)")
        }
    }
    
    // Map View Functions
    
    // User locations are shown
    func addAnnotations() {
        for i in 0 ..< userLocations.count {
            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(
                latitude: userLocations[i].value(forKey: "lat")! as! CLLocationDegrees,
                longitude: userLocations[i].value(forKey: "long")! as! CLLocationDegrees)
            annotation.title = "\(userLocations[i].value(forKey: "name")!)"
            mapView.addAnnotation(annotation)
        }
    }
    
    // Generates trial of points walked
    func generateLine() {
        mapView.delegate = self
        mapView.isZoomEnabled = true
        let polyline = MKPolyline(coordinates: coords, count: coords.count)
        mapView.addOverlay(polyline)
        zoomToPolyLine(map: mapView, polyLine: polyline)
        mapView.isZoomEnabled = false
    }
    
    func zoomToPolyLine(map : MKMapView, polyLine : MKPolyline) {
        var regionRect = polyLine.boundingMapRect

        let wPadding = regionRect.size.width * 0.75
        let hPadding = regionRect.size.height * 0.75

        // Add padding to the region
        regionRect.size.width += wPadding
        regionRect.size.height += hPadding

        // Center the region on the line
        regionRect.origin.x -= wPadding / 2
        regionRect.origin.y -= hPadding / 2

        mapView.setRegion(MKCoordinateRegion(regionRect), animated: true)
    }
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if overlay is MKPolyline {
            let polylineRenderer = MKPolylineRenderer(overlay: overlay)
            polylineRenderer.strokeColor = .red
            polylineRenderer.lineWidth = 4
            return polylineRenderer
        }
        return MKPolylineRenderer()
    }
    
    // Updates the labels
    func updateLabels() {
        distanceLabel.text = "Distance Walked: \(String(totalDistanceCalculated().truncate(places: 2))) mi"
        stepsLabel.text = "Steps Taken: \(self.steps) steps"
        distanceLabel.center.x = self.view.center.x
        stepsLabel.center.x = self.view.center.x
    }
    
    // Currently testing
    func voiceResults() {
        if (getState()) {
            let result = "You walked \(totalDistanceCalculated().truncate(places: 2)) miles and took \(String(describing: self.steps)) steps"
            let utterance = AVSpeechUtterance(string: result)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")

            let synthesizer = AVSpeechSynthesizer()
            synthesizer.speak(utterance)
        }
    }
    
    /**
       Converts meters to miles
        - Returns: A int containing the distance traveled (in miles)
    */
    func totalDistanceCalculated() -> Double {
        var total: Double
        total = Double(distance) / 1600
        return total
    }
    
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
    
    func getState() -> Bool {
        let defaults = UserDefaults.standard
        let gesture = defaults.bool(forKey: "state")
        return gesture
    }

}

extension Double {
    // Truncates double to how ever many places is needed
    // Used to manage the text to speech feature
    func truncate(places : Int) -> Double {
        return Double(floor(pow(10.0, Double(places)) * self) / pow(10.0, Double(places)))
    }
}

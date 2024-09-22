//
//  AppDelegate.swift
//  RealityMixerVisionPro
//
//  Created by Fabio Dela Antonio on 22/09/2024.
//

import UIKit

struct Style {
    static let navigationBarBackgroundColor = UIColor(white: 0.1, alpha: 1.0)
    static let navigationBarButtonColor = UIColor.white

    static let segmentedControlSelectedTextColor = UIColor.white
    static let segmentedControlNormalTextColor = UIColor.lightGray
}

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let titleTextAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: UIColor.white
        ]

        let largeTitleTextAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 30, weight: .regular),
            .foregroundColor: UIColor.white
        ]

        let standard = UINavigationBarAppearance()
        standard.titleTextAttributes = titleTextAttributes
        standard.largeTitleTextAttributes = largeTitleTextAttributes
        standard.shadowColor = Style.navigationBarBackgroundColor
        standard.backgroundColor = Style.navigationBarBackgroundColor

        UINavigationBar.appearance().standardAppearance = standard
        UINavigationBar.appearance().tintColor = Style.navigationBarButtonColor
        UINavigationBar.appearance().isTranslucent = true

        UISegmentedControl.appearance().setTitleTextAttributes(
            [ .foregroundColor: Style.segmentedControlSelectedTextColor ],
            for: .selected
        )

        UISegmentedControl.appearance().setTitleTextAttributes(
            [ .foregroundColor: Style.segmentedControlNormalTextColor ],
            for: .normal
        )

        let window = UIWindow(frame: UIScreen.main.bounds)
        self.window = window
        window.rootViewController = UINavigationController(rootViewController: InitialViewController())
        window.makeKeyAndVisible()
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }


}


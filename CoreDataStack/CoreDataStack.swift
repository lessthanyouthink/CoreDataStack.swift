//
//  CoreDataStack.swift
//  CoreDataStack
//
//  Created by Charles Joseph on 2015-12-04.
//  Copyright © 2015 Charles Joseph. All rights reserved.
//

import Foundation
import CoreData

public func contextForCurrentThread() throws -> NSManagedObjectContext {
    if let stack = CoreDataStack.mainStack {
        return stack.contextForCurrentThread()
    }
    else {
        throw NSError(domain: "com.cjoseph.coredatastack", code: 0, userInfo: [NSLocalizedDescriptionKey: "CoreDataStack.mainStack has not been set to a valid stack instance."])
    }
}

public class CoreDataStack: NSObject {
    public static var mainStack: CoreDataStack?
    
    public let managedObjectContext: NSManagedObjectContext
    let persistentStoreCoordinator: NSPersistentStoreCoordinator
    
    private var _threadDictionariesWithManagedObjectContexts = Set<NSMutableDictionary>()
    private let _lockQueue = dispatch_queue_create("com.cjoseph.coredatastack", DISPATCH_QUEUE_SERIAL)
    
    public convenience init(modelURL: NSURL, storeURL: NSURL?, storeType: String = NSSQLiteStoreType, eraseStoreOnError: Bool = false) {
        let model = NSManagedObjectModel.init(contentsOfURL: modelURL)
        
        let coordinator = NSPersistentStoreCoordinator.init(managedObjectModel: model!)
        do {
            try coordinator.addPersistentStoreWithType(storeType, configuration: nil, URL: storeURL, options: nil)
        }
        catch {
            var dict = [NSLocalizedDescriptionKey: "Failed to initialize the application's saved data"]
            dict[NSLocalizedFailureReasonErrorKey] = "There was an error creating or loading the application's saved data."
            dict[NSUnderlyingErrorKey] = "\(error)"
            
            if eraseStoreOnError && (storeURL != nil) {
                print("Error: \(dict)\n\n Now deleting and recreating the store.")
            
                do {
                    try NSFileManager.defaultManager().removeItemAtURL(storeURL!)
                    try coordinator.addPersistentStoreWithType(storeType, configuration: nil, URL: storeURL, options: nil)
                }
                    
                catch {
                    print("Error, aborting: \(error)")
                    abort()
                }
            }
            else {
                print("Error, aborting: \(error)")
                abort()
            }
        }
        
        self.init(persistentStoreCoordinator: coordinator)
    }
    
    public init(persistentStoreCoordinator: NSPersistentStoreCoordinator) {
        self.persistentStoreCoordinator = persistentStoreCoordinator
        
        var context: NSManagedObjectContext?
        
        let createContext = {
            context = NSManagedObjectContext.init(concurrencyType: .MainQueueConcurrencyType)
            context?.persistentStoreCoordinator = persistentStoreCoordinator
            context?.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        }
        
        if NSThread.isMainThread() {
            createContext()
        }
        else {
            dispatch_sync(dispatch_get_main_queue(), createContext)
        }

        managedObjectContext = context!
        
        super.init()
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "threadWillExit:", name: NSThreadWillExitNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "managedObjectContextUpdated:", name: NSManagedObjectContextDidSaveNotification, object: nil)
    }
    
    deinit {
        dispatch_sync(_lockQueue, {
            for dictionary in self._threadDictionariesWithManagedObjectContexts {
                dictionary.removeObjectForKey(self.description)
            }
        })
    }
    
    public func contextForCurrentThread() -> NSManagedObjectContext {
        if NSThread.isMainThread() {
            return managedObjectContext
        }
        else if let context = NSThread.currentThread().threadDictionary[self.description] as? NSManagedObjectContext {
            return context
        }
        else {
            let context = NSManagedObjectContext.init(concurrencyType: .PrivateQueueConcurrencyType)
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            context.persistentStoreCoordinator = persistentStoreCoordinator
            self.storeContextForCurrentThread(context)
            
            return context
        }
    }
    
    private func storeContextForCurrentThread(context: NSManagedObjectContext) {
        let threadDictionary = NSThread.currentThread().threadDictionary
        threadDictionary[self.description] = context
        dispatch_sync(_lockQueue, {
            self._threadDictionariesWithManagedObjectContexts.insert(threadDictionary)
        })
    }
    
    @objc private func managedObjectContextUpdated(notification: NSNotification) {
        if let context = notification.object as? NSManagedObjectContext {
            if context === managedObjectContext {
                return
            }
            
            if context.persistentStoreCoordinator != persistentStoreCoordinator {
                return
            }
            
            dispatch_async(dispatch_get_main_queue(), {
                self.managedObjectContext.mergeChangesFromContextDidSaveNotification(notification)
            })
        }
    }
    
    @objc private func threadWillExit(notification: NSNotification) {
        if let thread = notification.object as? NSThread {
            if thread.threadDictionary[self.description] != nil {
                thread.threadDictionary.removeObjectForKey(self.description)
                dispatch_sync(_lockQueue, {
                    self._threadDictionariesWithManagedObjectContexts.remove(thread.threadDictionary)
                })
            }
        }
    }
}
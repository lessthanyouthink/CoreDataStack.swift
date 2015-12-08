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
    
    lazy public private(set) var managedObjectContext: NSManagedObjectContext = {
        var context: NSManagedObjectContext?
        
        let createContext = {
            context = NSManagedObjectContext.init(concurrencyType: .MainQueueConcurrencyType)
            context?.persistentStoreCoordinator = self.persistentStoreCoordinator
            context?.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            self.storeContextForCurrentThread(context!)
        }
        
        if NSThread.isMainThread() {
            createContext()
        }
        else {
            dispatch_sync(dispatch_get_main_queue(), createContext)
        }
        
        return context!
    }()
    
    lazy var managedObjectModel: NSManagedObjectModel = {
       NSManagedObjectModel.init(contentsOfURL: self._modelURL)!
    }()
    
    lazy var persistentStoreCoordinator: NSPersistentStoreCoordinator = {
        var coordinator: NSPersistentStoreCoordinator = NSPersistentStoreCoordinator.init(managedObjectModel: self.managedObjectModel)
        do {
            try coordinator.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: self._storeURL, options: nil)
        }
        catch {
            var dict = [NSLocalizedDescriptionKey: "Failed to initialize the application's saved data"]
            dict[NSLocalizedFailureReasonErrorKey] = "There was an error creating or loading the application's saved data."
            dict[NSUnderlyingErrorKey] = "\(error)"
            print("Error: \(dict)\n\n Now deleting and recreating the database.")
            
            do {
                try NSFileManager.defaultManager().removeItemAtURL(self._storeURL)
                try coordinator.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: self._storeURL, options: nil)
            }
            
            catch {
                print("Error, aborting: \(error)")
                abort()
            }
        }
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "managedObjectContextUpdated:", name: NSManagedObjectContextDidSaveNotification, object: nil)
        
        return coordinator
    }()
    
    private var _modelURL: NSURL
    private var _storeURL: NSURL
    private var _threadDictionariesWithManagedObjectContexts = Set<NSMutableDictionary>()
    private let _lockQueue = dispatch_queue_create("com.cjoseph.coredatastack", DISPATCH_QUEUE_SERIAL)
    
    public init(modelURL: NSURL, storeURL: NSURL) {
        _modelURL = modelURL
        _storeURL = storeURL
        super.init()
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "threadWillExit:", name: NSThreadWillExitNotification, object: nil)
    }
    
    deinit {
        dispatch_sync(_lockQueue, {
            for dictionary in self._threadDictionariesWithManagedObjectContexts {
                dictionary.removeObjectForKey(self.description)
            }
        })
    }
    
    public func contextForCurrentThread() -> NSManagedObjectContext {
        var context = NSThread.currentThread().threadDictionary[self.description] as? NSManagedObjectContext
        
        if context != nil {
            return context!
        }
        else if NSThread.isMainThread() {
            return managedObjectContext
        }
        else {
            context = NSManagedObjectContext.init(concurrencyType: .PrivateQueueConcurrencyType)
            context?.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            context?.persistentStoreCoordinator = persistentStoreCoordinator
            self.storeContextForCurrentThread(context!)
            
            return context!
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
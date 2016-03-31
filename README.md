# CoreDataStack.swift [![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)

A simple Swift module for managing your Core Data stack and keeping track of different threads’ NSManagedContexts. Simply initialize a CoreDataStack instance with the URLs to your local model and store files, set it as the main stack, and use ```contextForCurrentThread()``` as needed.

This project is an experiment in rewriting the Core Data helper code I’ve used across a few different projects as something more modular and reusable (and in Swift!), rather than cluttering up the application delegate with a ton of boilerplate. The basic idea for how the contexts are used across threads is based on work from several years ago by my friend [Jim Dovey](https://github.com/AlanQuatermain).

It’s currently a little rough around the edges, and I’m not yet using this Swift version in production, but I thought it might be useful to share here for others to use or leave feedback.

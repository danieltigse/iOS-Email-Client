//
//  mailboxData.swift
//  iOS-Email-Client
//
//  Created by Pedro Aim on 4/22/18.
//  Copyright © 2018 Criptext Inc. All rights reserved.
//

import Foundation

class MailboxData {
    var selectedLabel = SystemLabel.inbox.id
    var emailArray = [Email]()
    var filteredEmailArray = [Email]()
    var emailReachedEnd = false
    var filteredReachedEnd = false
    var threadHash = [String:[Email]]()
    var threadToOpen:String?
    var isCustomEditing = false
    var unreadMails = 0
    var reachedEnd : Bool {
        get {
            return searchMode ? filteredReachedEnd : emailReachedEnd
        }
        set(reached) {
            if(searchMode){
                filteredReachedEnd = reached
            } else {
                emailReachedEnd = reached
            }
        }
    }
    var removeSelectedRow = false
    var fetchWorker: DispatchWorkItem?
    var searchMode = false
    var emails: [Email] {
        get {
            return searchMode ? filteredEmailArray : emailArray
        }
        set(newEmails) {
            if(searchMode){
                filteredEmailArray = newEmails
            } else {
                emailArray = newEmails
            }
        }
    }
    
    func cancelFetchWorker(){
        fetchWorker?.cancel()
        fetchWorker = nil
    }
}

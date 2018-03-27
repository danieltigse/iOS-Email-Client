//
//  ViewController.swift
//  Criptext Secure Email

//
//  Created by Gianni Carlo on 3/3/17.
//  Copyright © 2017 Criptext Inc. All rights reserved.
//

import UIKit
import Material
import SDWebImage
import SwiftWebSocket
import MIBadgeButton_Swift
import SwiftyJSON

//delete
import RealmSwift

class InboxViewController: UIViewController {
    
    @IBOutlet weak var tableView: UITableView!
    let refreshControl = UIRefreshControl()
    @IBOutlet weak var topToolbar: NavigationToolbarView!
    @IBOutlet weak var buttonCompose: UIButton!
    
    var currentUser: User!
    
    var selectedLabel = MyLabel.inbox
    
    var emailArray = [Email]()
    var filteredEmailArray = [Email]()
    var threadHash = [String:[Email]]()
    var attachmentHash = DBManager.getAllAttachments()
    var activities = DBManager.getAllActivities()
    var searchNextPageToken: String?
    
    var searchController = UISearchController(searchResultsController: nil)
    var spaceBarButton:UIBarButtonItem!
    var fixedSpaceBarButton:UIBarButtonItem!
    var flexibleSpaceBarButton:UIBarButtonItem!
    var cancelBarButton:UIBarButtonItem!
    var searchBarButton:UIBarButtonItem!
    var activityBarButton:UIBarButtonItem!
    var composerBarButton:UIBarButtonItem!
    var trashBarButton:UIBarButtonItem!
    var archiveBarButton:UIBarButtonItem!
    var moveBarButton:UIBarButtonItem!
    var markBarButton:UIBarButtonItem!
    var deleteBarButton:UIBarButtonItem!
    var menuButton:UIBarButtonItem!
    var counterBarButton:UIBarButtonItem!
    var titleBarButton = UIBarButtonItem(title: "INBOX", style: .plain, target: nil, action: nil)
    var countBarButton = UIBarButtonItem(title: "(12)", style: .plain, target: nil, action: nil)
    
    var footerView:UIView!
    var footerActivity:UIActivityIndicatorView!
    
    var threadToOpen:String?
    
    let statusBarButton = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)
    
    var ws:WebSocket!
    
    var originalNavigationRect:CGRect!
    var isCustomEditing = false
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    //MARK: - View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
//        CriptextSpinner.show(in: self.view, title: nil, image: UIImage(named: "icon_sent_chat.png"))
        
        self.navigationController?.navigationBar.addSubview(self.topToolbar)
        let margins = self.navigationController!.navigationBar.layoutMarginsGuide
        self.topToolbar.leadingAnchor.constraint(equalTo: margins.leadingAnchor, constant: -8.0).isActive = true
        self.topToolbar.trailingAnchor.constraint(equalTo: margins.trailingAnchor, constant: 8.0).isActive = true
        self.topToolbar.bottomAnchor.constraint(equalTo: margins.bottomAnchor, constant: 8.0).isActive = true
        self.navigationController?.navigationBar.bringSubview(toFront: self.topToolbar)
        
        self.footerView = UIView(frame: CGRect(x: 0, y: 0, width: self.tableView.frame.size.width, height: 40.0))
        self.footerView.backgroundColor = UIColor.clear
        self.footerActivity = UIActivityIndicatorView(activityIndicatorStyle: .gray)
        self.footerActivity.hidesWhenStopped = true
        self.footerView.addSubview(self.footerActivity)
        self.footerActivity.center = self.footerView.center
        self.tableView.tableFooterView = self.footerView
        
        self.originalNavigationRect = self.navigationController?.navigationBar.frame
        
        self.startNetworkListener()
        
        self.searchController.searchResultsUpdater = self as UISearchResultsUpdating
        self.searchController.dimsBackgroundDuringPresentation = false
        self.searchController.searchBar.delegate = self
        definesPresentationContext = true
        
        self.navigationItem.searchController = self.searchController
        self.refreshControl.addTarget(self, action: #selector(self.handleRefresh(_:automatic:signIn:completion:)), for: UIControlEvents.valueChanged)
        
        self.tableView.allowsMultipleSelection = true

        self.initBarButtonItems()
        
        self.currentUser = DBManager.getUsers().first
        
        self.setButtonItems(isEditing: false)
        self.loadMails(from: .inbox, since: Date())
        
        self.navigationItem.leftBarButtonItems = [self.menuButton, self.fixedSpaceBarButton, self.titleBarButton, self.countBarButton]
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.emailTrashed), name: NSNotification.Name(rawValue: "EmailTrashed"), object: nil)
        
        self.initFloatingButton()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        guard let indexPath = self.tableView.indexPathForSelectedRow, !self.isCustomEditing else {
            return
        }
        
        self.tableView.deselectRow(at: indexPath, animated: true)
        
        guard let indexArray = self.tableView.indexPathsForVisibleRows,
            let index = indexArray.first,
            index.row == 0,
            !self.searchController.isActive else {
            return
        }
        
    }
    
    // When the view appears, ensure that the Gmail API service is authorized
    // and perform API calls
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if self.emailArray.count > 0 {
            self.updateBadge(self.currentUser.badge)
            
            guard let date = self.currentUser.getUpdateDate(for: self.selectedLabel) else {
                self.statusBarButton.title = nil
//                self.handleRefresh(self.tableView.refreshControl!, automatic: true, signIn: false, completion: nil)
                return
            }
            
            if let earlyDate = Calendar.current.date(byAdding: .minute, value: -1, to: Date()), earlyDate > date {
                self.handleRefresh(self.refreshControl, automatic: true, signIn: false, completion: nil)
            } else {
                self.statusBarButton.title = String(format:"Updated %@",DateUtils.beatyDate(date))
            }
        }
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        self.footerView.frame = CGRect(origin: self.footerView.frame.origin, size: CGSize(width: size.width, height: self.footerView.frame.size.height) )
        
        self.footerActivity.frame = CGRect(origin: self.footerActivity.frame.origin, size: CGSize(width: size.width / 2, height: self.footerActivity.frame.size.height) )
    }
    
    func initBarButtonItems(){
        self.spaceBarButton = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil)
        self.fixedSpaceBarButton = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: self, action: nil)
        self.fixedSpaceBarButton.width = 25.0
        self.flexibleSpaceBarButton = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil)
        
//        self.cancelBarButton = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(didPressEdit))
        let derp = UIButton(type: .custom)
        derp.frame = CGRect(x: 0, y: 0, width: 31, height: 31)
        derp.setImage(#imageLiteral(resourceName: "menu-back"), for: .normal)
        derp.layer.backgroundColor = UIColor.red.cgColor
        derp.layer.cornerRadius = 15.5
        derp.addTarget(self, action: #selector(didPressEdit), for: .touchUpInside)
        
        self.cancelBarButton = UIBarButtonItem(customView: derp)
        
        self.trashBarButton = UIBarButtonItem(image: #imageLiteral(resourceName: "delete-icon"), style: .plain, target: self, action: #selector(didPressTrash))
        self.trashBarButton.tintColor = UIColor.white
        
        self.trashBarButton.isEnabled = false
        self.archiveBarButton = UIBarButtonItem(image: #imageLiteral(resourceName: "archive-icon"), style: .plain, target: self, action: #selector(didPressArchive))
        self.archiveBarButton.tintColor = UIColor.white
        self.archiveBarButton.isEnabled = false
        
        self.markBarButton = UIBarButtonItem(image: #imageLiteral(resourceName: "mark_read"), style: .plain, target: self, action: #selector(didPressMark))
        
        self.deleteBarButton = UIBarButtonItem(image: #imageLiteral(resourceName: "delete-icon"), style: .plain, target: self, action: #selector(didPressDelete))
        self.deleteBarButton.tintColor = UIColor.white
        self.counterBarButton = UIBarButtonItem(title: nil, style: .plain, target: self, action: nil)
        self.counterBarButton.tintColor = Icon.system.color
        self.titleBarButton.setTitleTextAttributes([NSAttributedStringKey.font: UIFont(name: "NunitoSans-Bold", size: 16.0)!, NSAttributedStringKey.foregroundColor: UIColor.white], for: .disabled)
        self.titleBarButton.isEnabled = false
        
        self.countBarButton.tintColor = UIColor(red:0.73, green:0.73, blue:0.74, alpha:1.0)
        self.countBarButton.setTitleTextAttributes([NSAttributedStringKey.font: UIFont(name: "NunitoSans-Bold", size: 16.0)!, NSAttributedStringKey.foregroundColor: UIColor(red:0.73, green:0.73, blue:0.74, alpha:1.0)], for: .disabled)
        self.countBarButton.isEnabled = false
        
        let attributescounter = [NSAttributedStringKey.font: UIFont.boldSystemFont(ofSize: 20)]
        self.counterBarButton.setTitleTextAttributes(attributescounter, for: .normal)
        
        self.menuButton = UIBarButtonItem(image: #imageLiteral(resourceName: "menu_white"), style: .plain, target: self, action: #selector(didPressOpenMenu(_:)))
        self.menuButton.tintColor = UIColor.white
        self.searchBarButton = UIBarButtonItem(image: #imageLiteral(resourceName: "search"), style: .plain, target: self, action: #selector(didPressSearch(_:)))
        self.searchBarButton.tintColor = UIColor(red:0.73, green:0.73, blue:0.74, alpha:1.0)
        
        // Set batButtonItems
        let activityButton = MIBadgeButton(type: .custom)
        activityButton.badgeString = ""
        activityButton.frame = CGRect(x:0, y:0, width:16.8, height:20.7)
        activityButton.badgeEdgeInsets = UIEdgeInsetsMake(25, 12, 0, 10)
        activityButton.setImage(#imageLiteral(resourceName: "activity"), for: .normal)
        activityButton.tintColor = UIColor.white
        activityButton.addTarget(self, action: #selector(didPressActivity), for: UIControlEvents.touchUpInside)
        self.activityBarButton = UIBarButtonItem(customView: activityButton)
        
        self.activityBarButton.tintColor = UIColor.white
        
        let font:UIFont = Font.regular.size(13)!
        let attributes:[NSAttributedStringKey : Any] = [NSAttributedStringKey.font: font];
        self.statusBarButton.setTitleTextAttributes(attributes, for: .normal)
        self.statusBarButton.tintColor = UIColor.darkGray
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func initFloatingButton(){
        let shadowPath = UIBezierPath(rect: CGRect(x: 15, y: 15, width: 30, height: 30))
        buttonCompose.layer.shadowColor = UIColor(red: 0, green: 145/255, blue: 255/255, alpha: 1).cgColor
        buttonCompose.layer.shadowOffset = CGSize(width: 0.5, height: 0.5)  //Here you control x and y
        buttonCompose.layer.shadowOpacity = 1
        buttonCompose.layer.shadowRadius = 15 //Here your control your blur
        buttonCompose.layer.masksToBounds =  false
        buttonCompose.layer.shadowPath = shadowPath.cgPath
    }
    
    func startNetworkListener(){
        APIManager.reachabilityManager.startListening()
        APIManager.reachabilityManager.listener = { status in
            
            switch status {
            case .notReachable, .unknown:
                //do nothing
                self.showSnackbar("Offline", attributedText: nil, buttons: "", permanent: false)
                break
            default:
                //try to reconnect
                //retry saving drafts and sending emails
                break
            }
        }
    }
    
    func mockupMails(){
//        self.emailArray = [];
        let emailData = EmailDetailData()
        emailData.mockEmails()
        self.emailArray = emailData.emails
    }
}

//MARK: - Modify mails actions
extension InboxViewController{
    @objc func didPressEdit() {
        self.isCustomEditing = !self.isCustomEditing
//        self.tableView.setEditing(!self.tableView.isEditing, animated: true)
        
        if self.isCustomEditing {
            self.topToolbar.counterButton.title = "1"
            self.title = ""
            self.navigationItem.leftBarButtonItems = [self.cancelBarButton, self.counterBarButton]
            self.topToolbar.isHidden = false
        }else{
            self.topToolbar.isHidden = true
            self.navigationController?.navigationBar.isHidden = false
            self.navigationItem.leftBarButtonItems = [self.menuButton, self.fixedSpaceBarButton, self.titleBarButton, self.countBarButton]
            self.titleBarButton.title = self.selectedLabel.description.uppercased()
            self.navigationController?.navigationBar.frame = self.originalNavigationRect
//            self.title = self.selectedLabel.description
        }
        
        //disable toolbar buttons
        if !self.isCustomEditing {
            self.toggleToolbar(false)
        }
        
        self.setButtonItems(isEditing: self.isCustomEditing)
    }
    
    @IBAction func didPressComposer(_ sender: UIButton) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        
        let navComposeVC = storyboard.instantiateViewController(withIdentifier: "NavigationComposeViewController") as! UINavigationController
        let composeVC = navComposeVC.childViewControllers.first as! ComposeViewController
        let snackVC = SnackbarController(rootViewController: navComposeVC)
        
        self.navigationController?.childViewControllers.last!.present(snackVC, animated: true, completion: nil)
    }
    
    
    
    @objc func didPressActivity(_ sender: UIBarButtonItem) {
        
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let navigationView = storyboard.instantiateViewController(withIdentifier: "ActivityViewController") as! UINavigationController
        let activityVC = navigationView.childViewControllers.last as! ActivityViewController
        activityVC.user = self.currentUser
        
        let snackVC = SnackbarController(rootViewController: navigationView)
        
        DBManager.update(self.currentUser, badge: 0)
        self.updateBadge(self.currentUser.badge)
        self.navigationController?.childViewControllers.last!.present(snackVC, animated: true, completion: nil)
    }
    
    @objc func didPressArchive(_ sender: UIBarButtonItem) {
        guard let emailsIndexPath = self.tableView.indexPathsForSelectedRows,
            (self.selectedLabel == .inbox || self.selectedLabel == .junk) else {
                if self.isCustomEditing {
                    self.didPressEdit()
                }
            return
        }
        
//        self.emailArray.remove(at: indexPath.row)
        self.tableView.deleteRows(at: emailsIndexPath, with: .fade)
    }
    
    @objc func didPressTrash(_ sender: UIBarButtonItem) {
        guard let emailsIndexPath = self.tableView.indexPathsForSelectedRows else {
            if self.isCustomEditing {
                self.didPressEdit()
            }
            return
        }
        
//        let email = self.emailArray.remove(at: emailsIndexPath.first!.row)
        self.tableView.deleteRows(at: emailsIndexPath, with: .fade)
    }
    
    @objc func emailTrashed(notification:Notification) -> Void {
        guard let userInfo = notification.userInfo,
            let emailTrashed  = userInfo["email"] as? Email else {
                print("No userInfo found in notification")
                return
        }
        
        if let index = self.emailArray.index(of: emailTrashed) {
            self.emailArray.remove(at: index)
        }
        
        if var threadArray = self.threadHash[emailTrashed.threadId],
            let index = threadArray.index(of: emailTrashed) {
            threadArray.remove(at: index)
            self.threadHash[emailTrashed.threadId] = threadArray
        }
        
        self.tableView.reloadData()
    }
    
    @objc func didPressMove(_ sender: UIBarButtonItem) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        
        let moveVC = storyboard.instantiateViewController(withIdentifier: "MoveMailViewController") as! MoveMailViewController
        moveVC.selectedLabel = self.selectedLabel
        
        self.present(moveVC, animated: true, completion: nil)
    }
    
    @objc func didPressMark(_ sender: UIBarButtonItem) {
        
        guard let emailsIndexPath = self.tableView.indexPathsForSelectedRows else {
            return
        }
        
        var markRead = true
        
        let emails = emailsIndexPath.map { return self.emailArray[$0.row] }
        
        var count = 0
        
        if count == emails.count {
            markRead = false
        }
        
        
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        var title = "Unread"
        if markRead {
            title = "Read"
        }
        
        sheet.addAction(UIAlertAction(title: "Mark as \(title)" , style: .default) { (action) in
            self.didPressEdit()
            
            let emailThreadIds = emailsIndexPath.map { return self.emailArray[$0.row].threadId }
            
            var addLabels:[String]?
            var removeLabels:[String]?
            
            if markRead {
                removeLabels = [MyLabel.unread.id]
            } else {
                addLabels = [MyLabel.unread.id]
            }
        })
        
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        sheet.popoverPresentationController?.sourceView = self.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: Double(self.view.bounds.size.width / 2.0), y: Double(self.view.bounds.size.height-45), width: 1.0, height: 1.0)
        
        self.present(sheet, animated: true, completion: nil)
    }
    
    func didPressDeleteAll(_ sender: UIBarButtonItem) {
        
        if self.isCustomEditing {
            self.didPressEdit()
        }
        
        for email in self.emailArray {
            if let hashEmails = self.threadHash[email.threadId] {
                DBManager.delete(hashEmails)
            }
        }
        self.emailArray.removeAll()
        self.threadHash.removeAll()
        self.tableView.reloadData()
    }
    
    @objc func didPressDelete(_ sender: UIBarButtonItem) {
        guard let emailsIndexPath = self.tableView.indexPathsForSelectedRows else {
            if self.isCustomEditing {
                self.didPressEdit()
            }
            return
        }
        
        for indexPath in emailsIndexPath {
            let threadId = self.emailArray[indexPath.row].threadId
            
            if let hashEmails = self.threadHash[threadId] {
                DBManager.delete(hashEmails)
                self.threadHash.removeValue(forKey: threadId)
            }
            self.emailArray.remove(at: indexPath.row)
        }
        self.tableView.deleteRows(at: emailsIndexPath, with: .fade)
    }
    
}

//MARK: - Side menu events
extension InboxViewController {
    func didChange(_ label:MyLabel) {
        self.selectedLabel = label
        self.titleBarButton.title = label.description.uppercased()
        self.emailArray.removeAll()
        self.threadHash.removeAll()
        
        if self.isCustomEditing {
            self.didPressEdit()
        }
        
        self.tableView.reloadData()
        
        
        //        check if it should get emails or just handle refresh
        self.loadMails(from: label, since: Date())
        
        if let nextPageToken = self.currentUser.nextPageToken(for: self.selectedLabel), nextPageToken == "0" {
            let fullString = NSMutableAttributedString(string: "")
            
            let image1Attachment = NSTextAttachment()
            image1Attachment.image = #imageLiteral(resourceName: "load-arrow")
            
            let image1String = NSAttributedString(attachment: image1Attachment)
            
            fullString.append(image1String)
            fullString.append(NSAttributedString(string: " Refreshing \(label.description)..."))
            self.showSnackbar("", attributedText: fullString, buttons: "", permanent: true)
            self.getEmails("me", labels: [label.id], completion: nil)
            return
        }
        
        self.statusBarButton.title = nil
        self.refreshControl.beginRefreshing()
        self.handleRefresh(self.refreshControl, automatic: false, signIn: false, completion: nil)
        
    }
    
    @IBAction func didPressOpenMenu(_ sender: UIBarButtonItem) {
        self.navigationDrawerController?.toggleLeftView()
    }
    
    @IBAction func didPressSearch(_ sender: UIBarButtonItem) {
        self.searchController.searchBar.becomeFirstResponder()
    }
    
    func showSignature(){
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        
        let signatureVC = storyboard.instantiateViewController(withIdentifier: "SignatureViewController") as! SignatureViewController
        signatureVC.currentUser = self.currentUser
        
        self.navigationController?.childViewControllers.last!.present(signatureVC, animated: true, completion: nil)
    }
    
    func showHeader(){
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        
        let headerVC = storyboard.instantiateViewController(withIdentifier: "HeaderViewController") as! HeaderViewController
        headerVC.currentUser = self.currentUser
        
        self.navigationController?.childViewControllers.last!.present(headerVC, animated: true, completion: nil)
    }
    
    func showShareDialog(){
        
        let linkUrl = "https://criptext.com/getapp"
        let textInvite = "I'm using Criptext for Gmail, it allows me to have control over my emails. Install it now: "
        let htmlInvite = "<html><body><p>\(textInvite)</p><p><a href='\(linkUrl)'>\(linkUrl)</a></p></body></html>"
        
        let textItem = ShareActivityItemProvider(placeholderItem: "wat")
        
        textItem.invitationText = textInvite
        textItem.invitationTextMail = htmlInvite
        textItem.subject = "Criptext for Gmail Invitation"
        textItem.otherappsText = textInvite
        
        let urlItem = URLActivityItemProvider(placeholderItem: linkUrl)
        
        urlItem.urlInvite = URL(string: linkUrl)
        
        let shareVC = UIActivityViewController(activityItems: [textItem, urlItem], applicationActivities: nil)
        
        shareVC.excludedActivityTypes = [.airDrop, .assignToContact, .print, .saveToCameraRoll, .addToReadingList]
        
        shareVC.completionWithItemsHandler = { (type, completed, returnedItems, error) in
            if !completed {
                return
            }
            
            if type == .copyToPasteboard {
                self.showAlert(nil, message: "Copied to clipboard", style: .alert)
            }
        }
        
        shareVC.popoverPresentationController?.sourceView = self.view
        shareVC.popoverPresentationController?.sourceRect = CGRect(x: Double(self.view.bounds.size.width / 2.0), y: Double(self.view.bounds.size.height-45), width: 1.0, height: 1.0)
        
        self.navigationController?.childViewControllers.last!.present(shareVC, animated: true, completion: nil)
        
    }
    
    func showSupport(){
        
        let body = "Type your message here...<br><br><br><br><br><br><br>Do not write below this line.<br>*****************************<br> Version: 1.2<br> Device: \(systemIdentifier()) <br> OS: iOS \(UIDevice.current.systemVersion) <br> Account type: \(self.currentUser.statusDescription()) <br> Plan: \(self.currentUser.plan)"
        
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let navComposeVC = storyboard.instantiateViewController(withIdentifier: "NavigationComposeViewController") as! UINavigationController
        let composeVC = navComposeVC.childViewControllers.first as! ComposeViewController
        composeVC.loadViewIfNeeded()
        composeVC.addToken("support@criptext.com", value: "support@criptext.com", to: composeVC.toField)
        composeVC.subjectField.text = "Criptext iPhone Support"
        composeVC.editorView.html = body
        composeVC.thumbUpdated = true
        
        let snackVC = SnackbarController(rootViewController: navComposeVC)
        
        self.navigationController?.childViewControllers.last!.present(snackVC, animated: true, completion: nil)
    }
    
    func changeDefaultValue(_ isOn:Bool){
        DBManager.update(self.currentUser, switchValue: isOn)
    }
}

//MARK: - Unwind Segues
extension InboxViewController{
    //move mail, unwind segue
    @IBAction func selectedMailbox(_ segue:UIStoryboardSegue){
        let vc = segue.source as! MoveMailViewController
        
        guard let selectedMailbox = vc.selectedMailbox,
            let emailsIndexPath = self.tableView.indexPathsForSelectedRows else {
            return
        }
        
        if self.navigationController!.viewControllers.count > 1 {
            self.navigationController?.popViewController(animated: true)
        }
        
        if self.isCustomEditing {
            self.didPressEdit()
        }
        
        var removeLabels: [String]?
        
        if self.selectedLabel != .sent && self.selectedLabel != .draft {
            removeLabels = [self.selectedLabel.id]
        }
        
        for indexPath in emailsIndexPath {
            let threadId = self.emailArray[indexPath.row].threadId
            for hashEmail in self.threadHash[threadId]!{
                DBManager.updateEmail(id: hashEmail.key, addLabels: [selectedMailbox.id], removeLabels: removeLabels)
                
            }
        }
        self.emailArray.removeAll()
        self.threadHash.removeAll()
        self.loadMails(from: self.selectedLabel, since: Date())
        self.tableView.reloadData()
    }
}

//MARK: - Websocket
extension InboxViewController{
    func startWebSocket(){
        
        let defaults = UserDefaults.standard
        let since = defaults.integer(forKey: "lastSync")
        self.ws = WebSocket("wss://com.criptext.com:3000?user_id=\(self.currentUser.id)&session_id=\(NSUUID().uuidString)&since=\(since)", subProtocols:["criptext-protocol"])
        
        self.ws.event.open = {
            print("opened")
        }
        self.ws.event.close = { code, reason, clean in
            print("close")
            self.startWebSocket()
        }
        self.ws.event.error = { error in
            print("error \(error)")
        }
        self.ws.event.message = { message in
            guard let text = message as? String,
                let mails = JSON.parse(text).array else {
                    return
            }
            
            print("recv: \(text)")
            
            var shouldReload = false
            var lastSync = 0
            var totalMailOpens = 0
            for mail in mails {
                let cmd = mail["cmd"].intValue
                
                switch cmd {
                case Commands.userStatus.rawValue:
                    let newStatus = mail["args"]["msg"].intValue
                    DBManager.update(self.currentUser, status:newStatus)
                    
                    if let plan = mail["args"]["plan"].string {
                        
                        DBManager.update(self.currentUser, plan:plan.isEmpty ? "Free trial" : plan)
                    }
                    
                    let sideVC = self.navigationDrawerController?.leftViewController as! ListLabelViewController
                    sideVC.setUserAccount(self.currentUser)
                    
                case Commands.emailOpened.rawValue:
                    //[{"cmd":1,"args":{"uid_from":1,"uid_to":"100","location":"Gmail","expirationTime":"1987200","timestamp":1492039527,"msg":"www.dt89@gmail.com:967nl7v92fqrggb9j1ds1r7rzkdf6vfj2sf3l3di"},"timestamp":1492039527}]
                    totalMailOpens += 1
                    let token = mail["args"]["msg"].string?.components(separatedBy: ":")[1]
                    let location = mail["args"]["location"].string
                    let timestamp = mail["args"]["timestamp"].int
                    
                    if let activity = DBManager.getActivityBy(token!) {
                        var openArray = JSON(parseJSON: activity.openArraySerialized).arrayValue.map({$0.stringValue})
                        openArray.insert(String(format:"%@:%d",location!,timestamp!), at: 0)
                        DBManager.update(activity, openArraySerialized: openArray.description)
                        DBManager.update(activity, hasOpens: true)
                        DBManager.update(activity, isNew: false)
                        
                        var subject = activity.subject
                        
                        if subject.characters.count > 25 {
                            subject = subject.substring(to: subject.index(subject.startIndex, offsetBy: 25)) + "..."
                        }
                        
                        self.showSnackbar("📩 Email \"\(subject)\" was opened", attributedText: nil, buttons: "", permanent: false)
                    }
                    
                    //SEND NOTIFICATIONS TO ACTIVITY
                    NotificationCenter.default.post(name: Notification.Name.Activity.onMsgNotificationChange, object: nil, userInfo: ["token": token!])
                    
                    shouldReload = true
                    
                case Commands.emailUnsend.rawValue:
                    //[{"cmd":4,"args":{"uid_from":1,"uid_to":"100","timestamp":1492039527,"msg":<token>},"timestamp":1492039527}]
                    let token = mail["args"]["msg"].stringValue
                    if let activity = self.activities[token] {
                        DBManager.update(activity, exist: false)
                    }
                    
                    guard let email = DBManager.getMailBy(token: token) else {
                        break
                    }
                    
                    DBManager.update(email, snippet: "The content is no longer available")
                    
                    shouldReload = true
                    
                case Commands.fileOpened.rawValue:
                    //[{"cmd":2,"args":{"uid_from":1,"uid_to":"100","location":"Guayaquil, EC","timestamp":1492039785,"file_token":"f2ao1vzakh85mij1ds17wncb40qenkp661dcxr","email_token":"967nl7v92fqrggb9j1ds1r7rzkdf6vfj2sf3l3di","file_name":"7-Activity-Inbox.png"},"timestamp":1492039785}]
                    let mailToken = mail["args"]["email_token"].string
                    let fileToken = mail["args"]["file_token"].string
                    let location = mail["args"]["location"].string
                    let timestamp = mail["args"]["timestamp"].int
                    
                    if let attachment = DBManager.getAttachmentBy(fileToken!){
                        var openArray = JSON(parseJSON: attachment.openArraySerialized).arrayValue.map({$0.stringValue})
                        openArray.insert(String(format:"%@:%d",location!,timestamp!), at: 0)
                        DBManager.update(attachment, openArraySerialized: openArray.description)
                        
                        var filename = attachment.fileName
                        
                        if filename.characters.count > 30 {
                            filename = filename.substring(to: filename.index(filename.startIndex, offsetBy: 30)) + "..."
                        }
                        
                        self.showSnackbar("📎 File \"\(filename)\" was opened", attributedText: nil, buttons: "", permanent: false)
                    }
                    
                    //SEND NOTIFICATIONS TO ACTIVITY
                    NotificationCenter.default.post(name: Notification.Name.Activity.onFileNotificationChange, object: nil, userInfo: ["fileToken": fileToken!, "mailToken": mailToken!])
                    
                    shouldReload = true
                    
                case Commands.fileDownloaded.rawValue:
                    //[{"cmd":3,"args":{"uid_from":1,"uid_to":"100","location":"Guayaquil, EC","timestamp":1492039847,"file_token":"f2ao1vzakh85mij1ds17wncb40qenkp661dcxr","email_token":"967nl7v92fqrggb9j1ds1r7rzkdf6vfj2sf3l3di","file_name":"7-Activity-Inbox.png"},"timestamp":1492039847}]
                    let mailToken = mail["args"]["email_token"].string
                    let fileToken = mail["args"]["file_token"].string
                    let location = mail["args"]["location"].string
                    let timestamp = mail["args"]["timestamp"].int
                    
                    if let attachment = DBManager.getAttachmentBy(fileToken!) {
                        var downloadArray = JSON(parseJSON: attachment.downloadArraySerialized).arrayValue.map({$0.stringValue})
                        downloadArray.insert(String(format:"%@:%d",location!,timestamp!), at: 0)
                        DBManager.update(attachment, downloadArraySerialized: downloadArray.description)
                        
                        var filename = attachment.fileName
                        
                        if filename.characters.count > 30 {
                            filename = filename.substring(to: filename.index(filename.startIndex, offsetBy: 30)) + "..."
                        }
                        
                        self.showSnackbar("📎 File \"\(filename)\" was downloaded", attributedText: nil, buttons: "", permanent: false)
                    }
                    
                    //SEND NOTIFICATIONS TO ACTIVITY
                    NotificationCenter.default.post(name: Notification.Name.Activity.onFileNotificationChange, object: nil, userInfo: ["fileToken": fileToken!, "mailToken": mailToken!])
                    
                    shouldReload = true
                    
                case Commands.emailCreated.rawValue:
                    //[{"cmd":54,"args":{"uid_from":1,"uid_to":"100","timestamp":1492103587,"msg":"9814u5geuaulq5mij1gny37yfsnb0uoafrsh5mi:mayer@criptext.com"},"timestamp":1492103587}]
                    let token = mail["args"]["msg"].string?.components(separatedBy: ":")[0]
                    APIManager.getMailDetail(self.currentUser, token: token!, completion: { (error, attachments, activity) in
                        
                        if(error != nil){
                            return
                        }
                        
                        guard let activity = activity else {
                            return
                        }
                        
                        DBManager.store([activity])
                        
                        //SEND NOTIFICATIONS TO ACTIVITY
                        NotificationCenter.default.post(name: Notification.Name.Activity.onNewMessage, object: nil, userInfo: ["activity": activity])
                    })
                    
                case Commands.fileCreated.rawValue:
                    //[{"cmd":55,"args":{"uid_from":1,"uid_to":"100","timestamp":1492103609,"msg":"9814u5geuaulq5mij1gny37yfsnb0uoafrsh5mi"},"timestamp":1492103609}]
                    let token = mail["args"]["msg"].string
                    APIManager.getMailDetail(self.currentUser, token: token!, completion: { (error, attachments, activity) in
                        
                        if(error != nil){
                            return
                        }
                        
                        guard let attachmentArray = attachments else {
                            return
                        }
                        
                        DBManager.store(attachmentArray)
                        
                        //SEND NOTIFICATIONS TO ACTIVITY
                        NotificationCenter.default.post(name: Notification.Name.Activity.onNewAttachment, object: nil, userInfo: ["attachments": attachmentArray, "token": token!])
                    })
                    
                case Commands.emailMute.rawValue:
                    //{"cmd":5,"args":{"uid_from":156,"uid_to":"5634","timestamp":1499355531, "msg":{"tokens":"fyehrgfgnfyndwgtrt54g,5gyuetyehwgy5egtyg","mute":"0"}},"timestamp":1499355531}
                    guard let tokens = mail["args"]["msg"]["tokens"].string,
                        let mute = mail["args"]["msg"]["mute"].string else {
                        return
                    }
                    
                    let tokenArray = tokens.components(separatedBy: ",")
                    let isMuted = mute == "1"
                    
                    for token in tokenArray {
                        if let activity = self.activities[token] {
                            DBManager.update(activity, isMuted: isMuted)
                        }
                    }
                    
                    //SEND NOTIFICATIONS TO ACTIVITY
                    NotificationCenter.default.post(name: Notification.Name.Activity.onEmailMute, object: nil, userInfo: ["tokens": tokens, "mute": mute])
                    
                    break
                    
                default:
                    print("unsupported command")
                }
                lastSync = mail["timestamp"].intValue
            }
            
            //SAVE THE LAST SYNC
            defaults.set(lastSync, forKey: "lastSync")
            
            //UPDATE BADGE
            if(totalMailOpens > 0){
                DBManager.update(self.currentUser, badge: self.currentUser.badge + totalMailOpens)
                self.updateBadge(self.currentUser.badge)
            }
            
            guard shouldReload, let indexPaths = self.tableView.indexPathsForVisibleRows else {
                return
            }
            
            self.tableView.reloadRows(at: indexPaths, with: .automatic)
        }
        
    }
    
    func stopWebsocket(){
        self.ws.event.close = {_,_,_ in }
        self.ws.close()
    }
    
    func updateBadge(_ count: Int){
        
        let activityButton = self.activityBarButton?.customView as! MIBadgeButton?
        if(count == 0){
            activityButton?.badgeString = ""
        }
        else{
            activityButton?.badgeString = String(count)
        }
        
    }
}

//MARK: - UIBarButton layout
extension InboxViewController{
    func setButtonItems(isEditing: Bool){
        
        if(!isEditing){
            self.navigationItem.rightBarButtonItems = [self.activityBarButton, self.searchBarButton, self.spaceBarButton]
            return
        }
        
        var items:[UIBarButtonItem] = []
        
        switch self.selectedLabel {
        case .inbox:
            items = [self.markBarButton,
                     self.flexibleSpaceBarButton,
                     self.trashBarButton,
                     self.archiveBarButton,
                     self.spaceBarButton]
        case .sent, .draft:
            items = [self.trashBarButton,
                     self.spaceBarButton]
        case .trash, .junk:
            items = [self.deleteBarButton,
                     self.markBarButton, self.spaceBarButton]
        default:
            break
        }
        
        self.navigationItem.rightBarButtonItems = items
    }
    
    func toggleToolbar(_ isEnabled:Bool){
        switch self.selectedLabel {
        case .inbox:
            self.markBarButton.isEnabled = isEnabled
            self.archiveBarButton.isEnabled = isEnabled
            self.trashBarButton.isEnabled = isEnabled
        case .sent, .draft:
            self.trashBarButton.isEnabled = isEnabled
        case .junk, .trash:
            self.markBarButton.isEnabled = isEnabled
        default:
            break
        }
    }
}

//MARK: - Load mails
extension InboxViewController{
    func open(threadId:String) {
        
        guard let threadArray = self.threadHash[threadId],
            let firstMail = threadArray.first,
            let index = self.emailArray.index(of: firstMail) else {
                self.threadToOpen = threadId
            return
        }
        
        let indexPath = IndexPath(row: index, section: 0)
        print("selecting cell")
        
        self.tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
        self.tableView(self.tableView , didSelectRowAt: indexPath)
        
        self.threadToOpen = nil
    }
    
    func loadMails(from label:MyLabel, since date:Date){
        let tuple = DBManager.getMails(from: label, since: date, current: self.emailArray, current: self.threadHash)
        
        self.emailArray = tuple.1
        self.tableView.reloadData()
        return
        let tupleObject = DBManager.getMails(from: label, since: date, current: self.emailArray, current: self.threadHash)
        
        guard (tupleObject.1.count > 0 || tupleObject.0.count > 0) else {
            //no more emails in DB
            //fetch from cloud
            print("=== FETCHING MAILS FROM CLOUD")
            self.getEmails("me", labels: [self.selectedLabel.id], completion: nil)
            return
        }
        
        for threadObject in tupleObject.0 {
            if self.threadHash[threadObject.key] == nil {
                self.threadHash[threadObject.key] = []
                self.threadHash[threadObject.key]!.append(contentsOf: threadObject.value)
            }
            //do not add otherwise, fetching mails from DB guarantees to pull every mail for each thread
        }
        
        for email in tupleObject.1 {
            //verify this email isnt duplicate
            if !self.emailArray.contains(where: { $0.threadId == email.threadId }) {
                self.emailArray.append(email)
            }
        }
        
        self.emailArray.sort(by: { $0.date?.compare($1.date!) == ComparisonResult.orderedDescending })
        
        self.tableView.reloadData()
        CriptextSpinner.hide(from: self.view)
    }
    
    @objc func handleRefresh(_ refreshControl: UIRefreshControl, automatic:Bool = false, signIn:Bool = false, completion: (() -> Void)?){
        
        if !automatic {
            DBManager.restoreState(self.currentUser)
        }
        
//        if let nextPageToken = self.currentUser.nextPageToken(for: self.selectedLabel), nextPageToken == "0" {
//            let fullString = NSMutableAttributedString(string: "")
//
//            let image1Attachment = NSTextAttachment()
//            image1Attachment.image = #imageLiteral(resourceName: "down-arrow")
//
//            let image1String = NSAttributedString(attachment: image1Attachment)
//
//            fullString.append(image1String)
//            fullString.append(NSAttributedString(string: " Downloading emails..."))
//            self.showSnackbar("", attributedText: fullString, buttons: "", permanent: true)
//
//            self.getEmails("me", labels: [self.selectedLabel.id], completion: completion)
//            return
//        }
        
        guard !self.emailArray.isEmpty else {
            self.refreshControl.endRefreshing()
            self.hideSnackbar()
            return
        }
        
        if signIn {
            let fullString = NSMutableAttributedString(string: "")
            
            let image1Attachment = NSTextAttachment()
            image1Attachment.image = #imageLiteral(resourceName: "load-arrow")
            
            let image1String = NSAttributedString(attachment: image1Attachment)
            
            fullString.append(image1String)
            fullString.append(NSAttributedString(string: " Refreshing \(self.selectedLabel.description)..."))
            self.showSnackbar("", attributedText: fullString, buttons: "", permanent: true)
        }
        
        //get updates
        
        self.updateAppIcon()
    }

    
    // Used to fetch mails from cloud
    func getEmails(_ userId:String, labels:[String], completion: (() -> Void)?){
        
        guard let nextPageToken = self.currentUser.nextPageToken(for: self.selectedLabel) else {
            CriptextSpinner.hide(from: self.view)
            return
        }
        
        let fullString = NSMutableAttributedString(string: "")
        
        let image1Attachment = NSTextAttachment()
        image1Attachment.image = #imageLiteral(resourceName: "down-arrow")
        
        let image1String = NSAttributedString(attachment: image1Attachment)
        
        fullString.append(image1String)
        fullString.append(NSAttributedString(string: " Downloading emails..."))
        self.showSnackbar("", attributedText: fullString, buttons: "", permanent: true)
        
        let pageToken:String? = nextPageToken != "0" ? nextPageToken : nil
        
        self.footerActivity.startAnimating()
        APIManager.getMails(
            userId: userId,
            labels: labels,
            pageToken: pageToken
        ) { (parsedEmails, parsedContacts, error) in
            CriptextSpinner.hide(from: self.view)
            self.refreshControl.endRefreshing()
            self.footerActivity.stopAnimating()
            
            if let contacts = parsedContacts {
                DBManager.store(contacts)
            }
            
            guard var parsedEmails = parsedEmails else {
                print(String(describing: error?.localizedDescription))
                return
            }
            
//            if let firstEmail = parsedEmails.first,
//                firstEmail.historyId > self.currentUser.historyId(for: self.selectedLabel) {
//                DBManager.update(self.currentUser, historyId: firstEmail.historyId, label: self.selectedLabel)
//            }
            
//            DBManager.update(self.currentUser, nextPageToken: (ticket.fetchedObject as! GTLRGmail_ListThreadsResponse).nextPageToken, label: self.selectedLabel)
            let now = Date()
            DBManager.update(self.currentUser, updateDate: now, label: self.selectedLabel)
            self.statusBarButton.title = "Updated Just Now"
            
            self.hideSnackbar()
            self.addFetched(&parsedEmails)
            
            if let completionHandler = completion {
                completionHandler()
            }
        }
    }
    
    func addFetched(_ emails: inout [Email]){
//        for email in emails {
            //DBManager.store(email)
            //add to array
//        }
        
        self.emailArray.sort(by: { $0.date?.compare($1.date!) == ComparisonResult.orderedDescending })
        self.tableView.reloadData()
    }
}

//MARK: - Google SignIn Delegate
extension InboxViewController{
    
    //silent sign in callback
    func sign(_ user:User, _ error: Error!) {

        guard error == nil else{
            print(error.localizedDescription)
            return
        }
        
        //fetch user
        
        //setup badges for sideVC and profile Img
        self.startWebSocket()
        self.updateBadge(self.currentUser.badge)
        
        //if email array count > 0, fetch partial updates
        self.handleRefresh(self.refreshControl, automatic: true, signIn: true, completion: nil)
        
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        appDelegate.registerPushNotifications()
        
        self.updateAppIcon()
    }
    
    func signout(){
        self.stopWebsocket()
        DBManager.signout()
        UIApplication.shared.applicationIconBadgeNumber = 0
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        
        let vc = storyboard.instantiateInitialViewController()!
        
        self.navigationController?.childViewControllers.last!.present(vc, animated: true){
            let appDelegate = UIApplication.shared.delegate as! AppDelegate
            appDelegate.replaceRootViewController(vc)
        }
    }
}

//MARK: - GestureRecognizer Delegate
extension InboxViewController: UIGestureRecognizerDelegate {
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        
        let touchPt = touch.location(in: self.view)
        
        guard let tappedView = self.view.hitTest(touchPt, with: nil) else {
            return true
        }
        
        
//        if gestureRecognizer == self.dismissTapGestureRecognizer && tappedView.isDescendant(of: self.contactTableView) && !self.contactTableView.isHidden {
//            return false
//        }
        
        return true
    }
}

//MARK: - NavigationDrawerController Delegate
extension InboxViewController: NavigationDrawerControllerDelegate {
    func navigationDrawerController(navigationDrawerController: NavigationDrawerController, willOpen position: NavigationDrawerPosition) {
        self.updateAppIcon()
    }
    
    func updateAppIcon() {
        //check mails for badge
    }
    
    func navigationDrawerController(navigationDrawerController: NavigationDrawerController, didClose position: NavigationDrawerPosition) {
        guard position == .right,
            let feedVC = navigationDrawerController.rightViewController as? FeedViewController else {
            return
        }
        feedVC.feedsTableView.isEditing = false
    }
}

//MARK: - TableView Datasource
extension InboxViewController: UITableViewDataSource{
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "InboxTableViewCell", for: indexPath) as! InboxTableViewCell
        cell.delegate = self
        let email:Email
        if self.searchController.isActive && self.searchController.searchBar.text != "" {
            email = self.filteredEmailArray[indexPath.row]
        }else {
            email = self.emailArray[indexPath.row]
        }
        
        let isSentFolder = self.selectedLabel == .sent
        
        //Set colors to initial state
        cell.secureAttachmentImageView.tintColor = UIColor(red:0.84, green:0.84, blue:0.84, alpha:1.0)
        
        //Set row status
        if !email.unread || isSentFolder {
            cell.backgroundColor = UIColor(red:0.96, green:0.96, blue:0.96, alpha:1.0)
            cell.senderLabel.font = Font.regular.size(15)
        }else{
            cell.backgroundColor = UIColor.white
            cell.senderLabel.font = Font.bold.size(15)
        }
        
        cell.subjectLabel.text = email.subject == "" ? "(No Subject)" : email.subject
        
        cell.previewLabel.text = email.preview
        
        cell.dateLabel.text = DateUtils.conversationTime(email.date)
        
        
        
        let size = cell.dateLabel.sizeThatFits(CGSize(width: 130, height: 21))
        cell.dateWidthConstraint.constant = size.width
        
//        var senderText = (isSentFolder || self.selectedLabel == .draft) ? email.to : email.fromDisplayString
        
//        if self.currentUser.email == email.from && self.selectedLabel != .sent {
//            senderText = "me"
//        }
        
//        cell.senderLabel.text = senderText
//
//        if senderText.isEmpty {
//            cell.senderLabel.text = "No Recipients"
//        }
        
        if self.isCustomEditing {
            cell.avatarImageView.image = nil
            cell.avatarImageView.layer.borderWidth = 1.0
            cell.avatarImageView.layer.borderColor = UIColor.lightGray.cgColor
            cell.avatarImageView.layer.backgroundColor = UIColor.lightGray.cgColor
        } else {
            
            let initials = cell.senderLabel.text!.replacingOccurrences(of: "\"", with: "")
            cell.avatarImageView.setImageForName(string: initials, circular: true, textAttributes: nil)
            cell.avatarImageView.layer.borderWidth = 0.0
        }
        
        if !self.currentUser.isPro() {
//            cell.secureAttachmentImageView.tintColor = UIColor.gray
        }
        
        guard let emailArrayHash = self.threadHash[email.threadId], emailArrayHash.count > 1 else{
            cell.containerBadge.isHidden = true
            cell.badgeWidthConstraint.constant = 0
            return cell
        }
        
//        let names = emailArrayHash.map { (mail) -> String in
//            var senderText = mail.fromDisplayString
//
//            if self.currentUser.email == mail.from {
//                senderText = "me"
//            }
//
//            return senderText
//        }
//
//        cell.senderLabel.text = Array(Set(names)).joined(separator: ", ")
        
        //check if unread among thread mails
        if emailArrayHash.contains(where: { return $0.unread }) {
            cell.backgroundColor = UIColor(red:0.96, green:0.98, blue:1.00, alpha:1.0)
            cell.senderLabel.font = Font.bold.size(17)
            cell.subjectLabel.font = Font.bold.size(17)
        }
        
        cell.containerBadge.isHidden = false
        
        switch emailArrayHash.count {
        case _ where emailArrayHash.count > 9:
            cell.badgeWidthConstraint.constant = 20
            break
        case _ where emailArrayHash.count > 99:
            cell.badgeWidthConstraint.constant = 25
            break
        default:
            cell.badgeWidthConstraint.constant = 20
            break
        }
        
        cell.badgeLabel.text = String(emailArrayHash.count)
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if self.searchController.isActive && self.searchController.searchBar.text != "" {
            return self.filteredEmailArray.count
        }
        return self.emailArray.count
    }
}

//MARK: - TableView Delegate
extension InboxViewController: InboxTableViewCellDelegate, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
        return .none
    }
    
    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        return false
    }
    
    func tableViewCellDidLongPress(_ cell: InboxTableViewCell) {
        
        if self.isCustomEditing {
            return
        }
        
        self.didPressEdit()
        
        guard let indexPath = self.tableView.indexPath(for: cell) else {
            return
        }
        
        if self.tableView.indexPathsForSelectedRows == nil {
//            print("count \(indexPaths.count)")
            self.tableView.reloadData()
        }
        
        self.tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
        self.tableView(self.tableView , didSelectRowAt: indexPath)
    }
    
    func tableViewCellDidTap(_ cell: InboxTableViewCell) {
        guard let indexPath = self.tableView.indexPath(for: cell) else {
            return
        }
        
//        if self.tableView.isEditing {
//            
//            return
//        }
        
        if cell.isSelected {
            self.tableView.deselectRow(at: indexPath, animated: true)
            self.tableView(tableView, didDeselectRowAt: indexPath)
            return
        }
        
        self.tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
        self.tableView(self.tableView , didSelectRowAt: indexPath)
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        if self.isCustomEditing {
            guard let indexPaths = tableView.indexPathsForSelectedRows else {
                return
            }
            
            if indexPaths.count == 1 {
                self.toggleToolbar(true)
            }
            
            let cell = tableView.cellForRow(at: indexPath) as! InboxTableViewCell
            
            cell.avatarImageView.layer.backgroundColor = UIColor(red:0.00, green:0.57, blue:1.00, alpha:1.0).cgColor
            cell.avatarImageView.image = #imageLiteral(resourceName: "check")
            cell.avatarImageView.tintColor = UIColor.white
            
            
            self.topToolbar.counterButton.title = "\(indexPaths.count)"
            return
        }
        
        let email:Email
        if self.searchController.isActive && self.searchController.searchBar.text != "" {
            self.searchController.searchBar.resignFirstResponder()
            email = self.filteredEmailArray[indexPath.row]
        }else {
            email = self.emailArray[indexPath.row]
        }
        
        let emp = EmailDetailData()
        emp.emails = [email]
        
//        guard let emailArrayHash = self.threadHash[email.threadId] else{
//            return
//        }
        
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        
        if self.selectedLabel != .draft {
            let vc = storyboard.instantiateViewController(withIdentifier: "EmailDetailViewController") as! EmailDetailViewController
            vc.emailData = emp
            
//            vc.currentUser = self.currentUser
//            vc.currentEmail = email
//            vc.selectedLabel = self.selectedLabel
//            vc.currentEmailIndex = 0
            
            
            if !email.unread {
                self.navigationController?.pushViewController(vc, animated: true)
                return
            }
            
            //modify labels
            
            self.navigationController?.pushViewController(vc, animated: true)
            return
        }
        
        let navComposeVC = storyboard.instantiateViewController(withIdentifier: "NavigationComposeViewController") as! UINavigationController
        let vcDraft = navComposeVC.childViewControllers.first as! ComposeViewController
//        vcDraft.attachmentArray = Array(email.attachments)
        vcDraft.emailDraft = email
        vcDraft.isDraft = true
        vcDraft.loadViewIfNeeded()
//        for email in email.to.components(separatedBy: ",") {
//            if email.isEmpty {
//                continue
//            }
//            vcDraft.addToken(email, value: email, to: vcDraft.toField)
//        }
        
        if email.subject != "No Subject" {
            vcDraft.subjectField.text = email.subject
        } else if email.subject != "(No Subject)" {
            vcDraft.subjectField.text = email.subject
        }
        
        vcDraft.editorView.html = email.content
        vcDraft.isEdited = false
        
        let snackVC = SnackbarController(rootViewController: navComposeVC)
        
        self.navigationController?.childViewControllers.last!.present(snackVC, animated: true) {
            //needed here because rich editor triggers content change on did load
            vcDraft.isEdited = false
            vcDraft.scrollView.setContentOffset(CGPoint(x: 0, y: -64), animated: true)
        }
    }
    
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        
        guard self.isCustomEditing else {
            return
        }
        
        guard tableView.indexPathsForSelectedRows == nil else {
            self.topToolbar.counterButton.title = "\(tableView.indexPathsForSelectedRows!.count)"
            let cell = tableView.cellForRow(at: indexPath) as! InboxTableViewCell
            cell.avatarImageView.image = nil
            return
        }
        
        self.toggleToolbar(false)
        self.didPressEdit()
        self.tableView.reloadData()
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let lastEmail = (self.searchController.isActive  && self.searchController.searchBar.text != "") ? self.filteredEmailArray.last : self.emailArray.last,
            let threadEmailArray = self.threadHash[lastEmail.threadId], let firstThreadEmail = threadEmailArray.first else {
                return
        }
        
        let email:Email
        if self.searchController.isActive && self.searchController.searchBar.text != "" {
            email = self.filteredEmailArray[indexPath.row]
        }else {
            email = self.emailArray[indexPath.row]
        }
        if email == lastEmail {
            if(searchController.searchBar.text == ""){
                self.loadMails(from: self.selectedLabel, since: firstThreadEmail.date!)
            }
            else{
                self.loadSearchedMails()
            }
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 79.0
    }
    
    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        
        let email:Email
        if self.searchController.isActive && self.searchController.searchBar.text != "" {
            email = self.filteredEmailArray[indexPath.row]
        }else {
            email = self.emailArray[indexPath.row]
        }
        
        guard self.selectedLabel != .trash else {
            return []
        }
        
        let trashAction = UITableViewRowAction(style: UITableViewRowActionStyle.normal, title: "         ") { (action, index) in
            
            if self.searchController.isActive && self.searchController.searchBar.text != "" {
                let emailTmp = self.filteredEmailArray.remove(at: indexPath.row)
                guard let index = self.emailArray.index(of: emailTmp) else {
                    return
                }
                self.emailArray.remove(at: index)
            }else {
                self.emailArray.remove(at: indexPath.row)
            }
            
            self.tableView.deleteRows(at: [indexPath], with: .fade)
        }
        
        trashAction.backgroundColor = UIColor(patternImage: UIImage(named: "trash-action")!)
        
        return [trashAction];
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
}



//MARK: - Search Delegate
extension InboxViewController: UISearchResultsUpdating, UISearchBarDelegate {
    
    func updateSearchResults(for searchController: UISearchController) {
        filterContentForSearchText(searchText: searchController.searchBar.text!)
    }
    
    func filterContentForSearchText(searchText: String, scope: String = "All") {
        filteredEmailArray = emailArray.filter { email in
            return email.content.lowercased().contains(searchText.lowercased())
                || email.subject.lowercased().contains(searchText.lowercased())
        }
        
        self.tableView.reloadData()
        
        if(searchText != ""){
            self.searchNextPageToken = "0"
            self.loadSearchedMails()
        }
    }
    
    func loadSearchedMails(){
        //search emails
    }
    
    func addSearchedFetched(_ emails:[Email]){
        self.filteredEmailArray.removeAll()
        for email in emails {
            DBManager.store(email)
            
            if self.threadHash[email.threadId] == nil {
                self.threadHash[email.threadId] = []
            }
            
            var threadArray = self.threadHash[email.threadId]!
            
            if !threadArray.contains(email){
                self.threadHash[email.threadId]!.append(email)
            }
            
            threadArray.sort(by: { $0.date?.compare($1.date!) == ComparisonResult.orderedDescending })
            
            if !self.filteredEmailArray.contains(where: { $0.threadId == email.threadId }) {
                self.filteredEmailArray.append(email)
            }
            
            if let dummyEmail = self.filteredEmailArray.first(where: { $0.threadId == email.threadId }),
                let index = self.filteredEmailArray.index(of: dummyEmail), email.date! > dummyEmail.date! {
                self.filteredEmailArray[index] = email
            }
        }
        
        self.filteredEmailArray.sort(by: { $0.date?.compare($1.date!) == ComparisonResult.orderedDescending })
        
        self.tableView.reloadData()
    }
}

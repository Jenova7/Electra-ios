//
//  AccountViewController.swift
//  breadwallet
//
//  Created by Adrian Corscadden on 2016-11-16.
//  Copyright © 2016 breadwallet LLC. All rights reserved.
//

import UIKit
import BRCore
import MachO

class AccountViewController: UIViewController, Subscriber, Trackable {
    
    // MARK: - Public
    let currency: Currency
    var didTapMenu: (() -> Void)?
    
    init(currency: Currency, walletManager: WalletManager) {
        self.walletManager = walletManager
        self.currency = currency
        self.headerView = AccountHeaderView(currency: currency)
        self.footerView = AccountFooterView(currency: currency)
        super.init(nibName: nil, bundle: nil)
        self.transactionsTableView = TransactionsTableViewController(currency: currency, walletManager: walletManager, didSelectTransaction: didSelectTransaction)

        if let btcWalletManager = walletManager as? BTCWalletManager {
            headerView.isWatchOnly = btcWalletManager.isWatchOnly
        } else {
            headerView.isWatchOnly = false
        }

        footerView.sendCallback = { Store.perform(action: RootModalActions.Present(modal: .send(currency: self.currency))) }
        footerView.receiveCallback = { Store.perform(action: RootModalActions.Present(modal: .receive(currency: self.currency))) }
        footerView.buyCallback = { Store.perform(action: RootModalActions.Present(modal: .buy(currency: self.currency))) }
        footerView.sellCallback = { Store.perform(action: RootModalActions.Present(modal: .sell(currency: self.currency))) }
    }

    // MARK: - Private
    private let walletManager: WalletManager
    private let headerView: AccountHeaderView
    private let footerView: AccountFooterView
    private var footerHeightConstraint: NSLayoutConstraint?
    private let transitionDelegate = ModalTransitionDelegate(type: .transactionDetail)
    private var transactionsTableView: TransactionsTableViewController!
    private let searchHeaderview: SearchHeaderView = {
        let view = SearchHeaderView()
        view.isHidden = true
        return view
    }()
    private let headerContainer = UIView()
    private var loadingTimer: Timer?
    private var shouldShowStatusBar: Bool = true {
        didSet {
            if oldValue != shouldShowStatusBar {
                UIView.animate(withDuration: C.animationDuration) {
                    self.setNeedsStatusBarAppearanceUpdate()
                }
            }
        }
    }
    private var notificationObservers = [String: NSObjectProtocol]()
    private var tableViewTopConstraint: NSLayoutConstraint?
    private var rewardsViewHeightConstraint: NSLayoutConstraint?
    private var rewardsView: RewardsView?
    private let rewardsAnimationDuration: TimeInterval = 0.5
    private let rewardsShrinkTimerDuration: TimeInterval = 6.0
    private let rewardsViewMargin: CGFloat = 16
    private var rewardsTappedEvent: String {
        return makeEventName([EventContext.rewards.name, Event.banner.name])
    }
    
    private func tableViewTopConstraintConstant(for rewardsViewState: RewardsView.State) -> CGFloat {
        let constant = rewardsViewState == .expanded ? RewardsView.expandedSize : RewardsView.normalSize
        return constant + rewardsViewMargin
    }
    
    private var shouldShowRewardsView: Bool {
        return Currencies.brd.code == currency.code
    }
    
    private var shouldAnimateRewardsView: Bool {
        return shouldShowRewardsView && UserDefaults.shouldShowBRDRewardsAnimation
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // detect jailbreak so we can throw up an idiot warning, in viewDidLoad so it can't easily be swizzled out
        if !E.isSimulator {
            var s = stat()
            var isJailbroken = (stat("/bin/sh", &s) == 0) ? true : false
            for i in 0..<_dyld_image_count() {
                guard !isJailbroken else { break }
                // some anti-jailbreak detection tools re-sandbox apps, so do a secondary check for any MobileSubstrate dyld images
                if strstr(_dyld_get_image_name(i), "MobileSubstrate") != nil {
                    isJailbroken = true
                }
            }
            notificationObservers[UIApplication.willEnterForegroundNotification.rawValue] =
                NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { _ in
                self.showJailbreakWarnings(isJailbroken: isJailbroken)
            }
            showJailbreakWarnings(isJailbroken: isJailbroken)
        }

        view.layer.contents =  #imageLiteral(resourceName: "Background").cgImage
        
        setupNavigationBar()
        addSubviews()
        addConstraints()
        addTransactionsView()
        addSubscriptions()
        setInitialData()
        
        if shouldShowRewardsView {
            addRewardsView()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        shouldShowStatusBar = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        headerView.setBalances()
        
        if walletManager.peerManager?.connectionStatus == BRPeerStatusDisconnected {
            DispatchQueue.walletQueue.async { [weak self] in
                self?.walletManager.peerManager?.connect()
            }
        }
        
        if shouldAnimateRewardsView {
            expandRewardsView()
        }
    }
    
    @available(iOS 11.0, *)
    override func viewSafeAreaInsetsDidChange() {
        footerHeightConstraint?.constant = AccountFooterView.height + view.safeAreaInsets.bottom
    }
    
    // MARK: -
    
    private func setupNavigationBar() {
        let searchButton = UIButton(type: .system)
        searchButton.setImage(#imageLiteral(resourceName: "SearchIcon"), for: .normal)
        searchButton.frame = CGRect(x: 0.0, y: 12.0, width: 22.0, height: 22.0) // for iOS 10
        searchButton.widthAnchor.constraint(equalToConstant: 22.0).isActive = true
        searchButton.heightAnchor.constraint(equalToConstant: 22.0).isActive = true
        searchButton.tintColor = .white
        searchButton.tap = showSearchHeaderView
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: searchButton)
        
        let menuButton = UIButton(type: .system)
        menuButton.setImage(#imageLiteral(resourceName: "menu_white"), for: .normal)
        menuButton.imageView?.contentMode = .scaleAspectFit
        menuButton.frame = CGRect(x: 0.0, y: 12.0, width: 22.0, height: 22.0) // for iOS 10
        menuButton.widthAnchor.constraint(equalToConstant: 22.0).isActive = true
        menuButton.heightAnchor.constraint(equalToConstant: 22.0).isActive = true
        
        menuButton.tintColor = .white
        menuButton.tap = menu
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: menuButton)

    }

    private func addSubviews() {
        view.addSubview(headerContainer)
        headerContainer.addSubview(headerView)
        headerContainer.addSubview(searchHeaderview)
        view.addSubview(footerView)
    }

    private func addConstraints() {
        let topConstraint = headerContainer.topAnchor.constraint(equalTo: view.topAnchor)
        topConstraint.priority = .required
        headerContainer.constrain([
            headerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topConstraint,
            headerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        headerView.constrain(toSuperviewEdges: nil)
        
        //searchHeaderview.constrain(toSuperviewEdges: nil)
        searchHeaderview.constrain([
            searchHeaderview.widthAnchor.constraint(equalTo: headerContainer.widthAnchor),
            searchHeaderview.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            searchHeaderview.topAnchor.constraint(equalTo: headerContainer.topAnchor, constant: 0)//100)
        ])

        footerHeightConstraint = footerView.heightAnchor.constraint(equalToConstant: AccountFooterView.height)
        footerView.constrain([
            footerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: -C.padding[1]),
            footerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: C.padding[1]),
            footerHeightConstraint ])
    }

    private func addSubscriptions() {
        Store.subscribe(self, name: .showStatusBar, callback: { _ in
            self.shouldShowStatusBar = true
        })
        Store.subscribe(self, name: .hideStatusBar, callback: { _ in
            self.shouldShowStatusBar = false
        })
    }

    private func setInitialData() {
        searchHeaderview.didCancel = hideSearchHeaderView
        searchHeaderview.didChangeFilters = { [weak self] filters in
            self?.transactionsTableView.filters = filters
        }
    }
    
    private func addTransactionsView() {

        // Store this constraint so it can be easily updated later when showing/hiding the rewards view.
        tableViewTopConstraint = transactionsTableView.view.topAnchor.constraint(equalTo: headerContainer.bottomAnchor)
        
        transactionsTableView.view.backgroundColor = .transparent

        addChildViewController(transactionsTableView, layout: {
            transactionsTableView.view.constrain([
                tableViewTopConstraint,
                transactionsTableView.view.bottomAnchor.constraint(equalTo: footerView.topAnchor),
                transactionsTableView.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                transactionsTableView.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)])
        })
    }
    
    private func didSelectTransaction(transactions: [Transaction], selectedIndex: Int) {
        let transactionDetails = TxDetailViewController(transaction: transactions[selectedIndex])
        transactionDetails.modalPresentationStyle = .overCurrentContext
        transactionDetails.transitioningDelegate = transitionDelegate
        transactionDetails.modalPresentationCapturesStatusBarAppearance = true
        present(transactionDetails, animated: true, completion: nil)
    }

    private func showJailbreakWarnings(isJailbroken: Bool) {
        guard isJailbroken else { return }
        let totalSent = walletManager.wallet?.totalSent ?? 0
        let message = totalSent > 0 ? S.JailbreakWarnings.messageWithBalance : S.JailbreakWarnings.messageWithBalance
        let alert = UIAlertController(title: S.JailbreakWarnings.title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: S.JailbreakWarnings.ignore, style: .default, handler: nil))
        if totalSent > 0 {
            alert.addAction(UIAlertAction(title: S.JailbreakWarnings.wipe, style: .default, handler: nil)) //TODO - implement wipe
        } else {
            alert.addAction(UIAlertAction(title: S.JailbreakWarnings.close, style: .default, handler: { _ in
                exit(0)
            }))
        }
        present(alert, animated: true, completion: nil)
    }
    
    private func showSearchHeaderView() {
        let navBarHeight: CGFloat = 44.0
        self.navigationController?.setNavigationBarHidden(true, animated: false)
        var contentInset = self.transactionsTableView.tableView.contentInset
        var contentOffset = self.transactionsTableView.tableView.contentOffset
        contentInset.top += navBarHeight
        contentOffset.y -= navBarHeight
        self.transactionsTableView.tableView.contentInset = contentInset
        self.transactionsTableView.tableView.contentOffset = contentOffset
        UIView.transition(from: self.headerView,
                          to: self.searchHeaderview,
                          duration: C.animationDuration,
                          options: [.transitionFlipFromBottom, .showHideTransitionViews, .curveEaseOut],
                          completion: { _ in
                            self.searchHeaderview.triggerUpdate()
                            //self.setNeedsStatusBarAppearanceUpdate()
        })
    }
    
    private func hideSearchHeaderView() {
        let navBarHeight: CGFloat = 44.0
        self.navigationController?.setNavigationBarHidden(false, animated: false)
        var contentInset = self.transactionsTableView.tableView.contentInset
        contentInset.top -= navBarHeight
        self.transactionsTableView.tableView.contentInset = contentInset
        UIView.transition(from: self.searchHeaderview,
                          to: self.headerView,
                          duration: C.animationDuration,
                          options: [.transitionFlipFromTop, .showHideTransitionViews, .curveEaseOut],
                          completion: { _ in
                           // self.setNeedsStatusBarAppearanceUpdate()
        })
    }
    
    // The rewards view is a separate UIView that is displayed in the BRD wallet,
    // under the table view header, above the transaction cells.
    private func addRewardsView() {
        
        let rewards = RewardsView()
        view.addSubview(rewards)
        rewardsView = rewards

        let rewardsViewTopConstraint = rewards.topAnchor.constraint(equalTo: headerView.bottomAnchor,
                                                                        constant: rewardsViewMargin / 2)
        
        // Start the rewards view at a height of zero if animating, otherwise at the normal height.
        let initialHeight = shouldAnimateRewardsView ? 0 : RewardsView.normalSize
        rewardsViewHeightConstraint = rewards.heightAnchor.constraint(equalToConstant: initialHeight)
        
        rewards.constrain([
            rewardsViewTopConstraint,
            rewardsViewHeightConstraint,
            rewards.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rewards.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        
        tableViewTopConstraint?.constant = shouldAnimateRewardsView ? 0 : tableViewTopConstraintConstant(for: .normal)

        view.layoutIfNeeded()
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self,
                                                          action: #selector(rewardsViewTapped))
        rewardsView?.addGestureRecognizer(tapGestureRecognizer)
    }

    private func expandRewardsView() {
        let constants = (tableViewTopConstraintConstant(for: .expanded), RewardsView.expandedSize)
        
        UIView.animate(withDuration: rewardsAnimationDuration, animations: { [unowned self] in
            self.tableViewTopConstraint?.constant = constants.0
            self.rewardsViewHeightConstraint?.constant = constants.1
            self.view.layoutIfNeeded()
        }, completion: { [unowned self] _ in
            self.rewardsView?.animateIcon()

            UserDefaults.shouldShowBRDRewardsAnimation = false

            Timer.scheduledTimer(withTimeInterval: self.rewardsShrinkTimerDuration, repeats: false) { [unowned self] _ in
                self.shrinkRewardsView()
            }
        })
    }
    
    private func shrinkRewardsView() {
        let constants = (tableViewTopConstraintConstant(for: .normal), RewardsView.normalSize)

        UIView.animate(withDuration: rewardsAnimationDuration, animations: {
            self.rewardsView?.shrinkView()
            self.tableViewTopConstraint?.constant = constants.0
            self.rewardsViewHeightConstraint?.constant = constants.1
            self.view.layoutIfNeeded()
        })
    }
    
    @objc private func rewardsViewTapped() {
        saveEvent(rewardsTappedEvent)
        Store.trigger(name: .openPlatformUrl("/rewards"))
    }
    
    @objc private func menu() { didTapMenu?() }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return searchHeaderview.isHidden ? .lightContent : .default
    }

    override var prefersStatusBarHidden: Bool {
        return !shouldShowStatusBar
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return .slide
    }

    deinit {
        notificationObservers.values.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

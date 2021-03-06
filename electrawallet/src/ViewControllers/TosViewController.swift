//
//  AboutViewController.swift
//  breadwallet
//
//  Created by Adrian Corscadden on 2017-04-05.
//  Copyright © 2017 breadwallet LLC. All rights reserved.
//

import UIKit
import SafariServices

class TosViewController: UIViewController, UITextViewDelegate {

    init(didTapNext: @escaping () -> Void) {
        self.didTapNext = didTapNext
        super.init(nibName: nil, bundle: nil)
    }
    
    init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    private var didTapNext: (() -> Void)? = nil
    private let titleLabel = UILabel(font: .customBold(size: 17.0), color: .white)
    private let scrollView = UIScrollView()
    private let text = UILabel()
    private let ackButton = UIButton.rounded(title: S.TosView.consent)

    override func viewDidLoad() {
        navigationItem.titleView = titleLabel
        addSubviews()
        addConstraints()
        setData()
    }

    private func addSubviews() {
        view.addSubview(scrollView)
        view.addSubview(ackButton)
        scrollView.addSubview(text)
    }

    private func addConstraints() {
        scrollView.constrain([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: (E.isIPhoneX ? C.padding[5] : C.padding[3]) + (didTapNext != nil ? 44 : 0)),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -C.padding[2]),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: C.padding[2]),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -C.padding[2])
        ])
        
        text.constrain([
            text.topAnchor.constraint(equalTo: scrollView.topAnchor),
            text.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            text.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            text.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            text.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
        
        ackButton.constrain([
            ackButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -C.padding[2]),
            ackButton.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.5),
            ackButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            ackButton.heightAnchor.constraint(equalToConstant: 44.0)
        ])


    }

    private func setData() {
        titleLabel.text = S.TosView.title
        view.layer.contents =  #imageLiteral(resourceName: "Background").cgImage
        ackButton.tap = didTapNext
        ackButton.isHidden = true
        scrollView.backgroundColor = .transparent
        text.backgroundColor = .transparent
        text.textColor = .white
        text.lineBreakMode = .byWordWrapping
        text.numberOfLines = 0
        text.textAlignment = .center
        text.text = S.TosView.agreement
        text.sizeToFit()
        
    }
    
    override func viewDidLayoutSubviews() {
        self.scrollView.delegate = self
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if (self.didTapNext != nil)
        {
            ackButton.isHidden = scrollView.contentOffset.y + scrollView.bounds.height < scrollView.contentSize.height
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

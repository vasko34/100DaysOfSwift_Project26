import SpriteKit
import CoreMotion

enum CollisionTypes: UInt32 {
    case player = 1
    case wall = 2
    case star = 4
    case vortex = 8
    case teleporter = 16
    case finish = 32
}

class GameScene: SKScene, SKPhysicsContactDelegate {
    var player: SKSpriteNode!
    var scoreLabel: SKLabelNode!
    var levelLabel: SKLabelNode!
    var lastTouchPosition: CGPoint?
    var motionManager: CMMotionManager?
    var teleporters: (CGPoint?, CGPoint?)
    var mapNodes = [SKNode]()
    var isGameOver = false
    var teleporterOff = false
    var level = 1 {
        didSet {
            levelLabel.text = "Level: \(level)"
        }
    }
    var score = 0 {
        didSet {
            scoreLabel.text = "Score: \(score)"
        }
    }
    
    override func didMove(to view: SKView) {
        let background = SKSpriteNode(imageNamed: "background")
        background.position = CGPoint(x: 512, y: 384)
        background.blendMode = .replace
        background.zPosition = -1
        addChild(background)
        
        scoreLabel = SKLabelNode(fontNamed: "Chalkduster")
        scoreLabel.position = CGPoint(x: 16, y: 16)
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.zPosition = 2
        addChild(scoreLabel)
        score = 0
        
        levelLabel = SKLabelNode(fontNamed: "Chalkduster")
        levelLabel.text = "Level: 1"
        levelLabel.position = CGPoint(x: 1000, y: 16)
        levelLabel.horizontalAlignmentMode = .right
        levelLabel.zPosition = 2
        addChild(levelLabel)
        
        if let levelURL = Bundle.main.url(forResource: "level1", withExtension: "txt") {
           loadLevel(levelURL: levelURL)
        }
        
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
        
        motionManager = CMMotionManager()
        motionManager?.startAccelerometerUpdates()
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        
        let location = touch.location(in: self)
        lastTouchPosition = location
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        
        let location = touch.location(in: self)
        lastTouchPosition = location
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastTouchPosition = nil
    }
    
    override func update(_ currentTime: TimeInterval) {
        guard !isGameOver else { return }
        
        #if targetEnvironment(simulator)
        if let lastTouchPosition = self.lastTouchPosition {
            let diff = CGPoint(x: lastTouchPosition.x - player.position.x, y: lastTouchPosition.y - player.position.y)
            physicsWorld.gravity = CGVector(dx: diff.x / 100, dy: diff.y / 100)
        }
        #else
        if let accelerometerData = motionManager?.accelerometerData {
            physicsWorld.gravity = CGVector(dx: accelerometerData.acceleration.y * -50, dy: accelerometerData.acceleration.x * 50)
        }
        #endif
    }
    
    func didBegin(_ contact: SKPhysicsContact) {
        guard let nodeA = contact.bodyA.node else { return }
        guard let nodeB = contact.bodyB.node else { return }
        
        if nodeA == player {
            playerCollided(with: nodeB)
        } else if nodeB == player {
            playerCollided(with: nodeA)
        }
    }
    
    func didEnd(_ contact: SKPhysicsContact) {
        guard let nodeA = contact.bodyA.node else { return }
        guard let nodeB = contact.bodyB.node else { return }
        
        if nodeA == player {
            if nodeB.name == "teleporter" {
                teleporterOff = false
            }
        } else if nodeB == player {
            if nodeA.name == "teleporter" {
                teleporterOff = false
            }
        }
    }
    
    func playerCollided(with node: SKNode) {
        if node.name == "vortex" {
            player.physicsBody?.isDynamic = false
            isGameOver = true
            score -= 1
            if score < 0 {
                score = 0
            }
            
            let move = SKAction.move(to: node.position, duration: 0.25)
            let scale = SKAction.scale(to: 0.0001, duration: 0.25)
            let remove = SKAction.removeFromParent()
            let sequence = SKAction.sequence([move, scale, remove])
            
            player.run(sequence) { [weak self] in
                self?.createPlayer()
                self?.isGameOver = false
            }
        } else if node.name == "star" {
            node.removeFromParent()
            score += 1
        } else if node.name == "finish" {
            player.physicsBody?.isDynamic = false
            isGameOver = true
            level += 1
            
            let move = SKAction.move(to: node.position, duration: 0.25)
            let remove = SKAction.removeFromParent()
            let sequence = SKAction.sequence([move, remove])
            
            if let nextLevel = Bundle.main.url(forResource: "level\(level)", withExtension: "txt") {
                player.run(sequence) { [weak self] in
                    self?.loadLevel(levelURL: nextLevel)
                }
            } else {
                level -= 1
                if let sameLevel = Bundle.main.url(forResource: "level\(level)", withExtension: "txt") {
                    player.run(sequence) { [weak self] in
                        self?.loadLevel(levelURL: sameLevel)
                    }
                }
            }
        } else if node.name == "teleporter" && !teleporterOff {
            player.physicsBody?.isDynamic = false
            isGameOver = true
            let move = SKAction.move(to: node.position, duration: 0.25)
            let remove = SKAction.removeFromParent()
            let sequence = SKAction.sequence([move, remove])
            
            if let teleporter0 = teleporters.0 {
                if let teleporter1 = teleporters.1 {
                    if abs(node.position.y - teleporter0.y) < 1 {
                        player.run(sequence) { [weak self] in
                            self?.createPlayer(at: teleporter1)
                            self?.isGameOver = false
                            self?.teleporterOff = true
                        }
                    } else if abs(node.position.y - teleporter1.y) < 1 {
                        player.run(sequence) { [weak self] in
                            self?.createPlayer(at: teleporter0)
                            self?.isGameOver = false
                            self?.teleporterOff = true
                        }
                    }
                }
            }
        }
    }
    
    func loadLevel(levelURL: URL) {
        guard let levelString = try? String(contentsOf: levelURL) else {
            fatalError("Could not load level from the app bundle.")
        }
        
        for node in mapNodes {
            node.removeFromParent()
        }
        mapNodes.removeAll()
        if player != nil {
            player.removeFromParent()
        }
        createPlayer()
        createMap(mapString: levelString)
        score = 0
        teleporterOff = false
        isGameOver = false
    }
    
    func createMap(mapString: String) {
        let lines = mapString.components(separatedBy: "\n")
        for (row, line) in lines.reversed().enumerated() {
            for (column, letter) in line.enumerated() {
                let position = CGPoint(x: (64 * column) + 32, y: (64 * row) + 32)
                
                if letter == "x" {
                    createWall(position: position)
                } else if letter == "v" {
                    createObject(position: position, name: "vortex", category: .vortex)
                } else if letter == "s" {
                    createObject(position: position, name: "star", category: .star)
                } else if letter == "f" {
                    createObject(position: position, name: "finish", category: .finish)
                } else if letter == "t" {
                    createObject(position: position, name: "teleporter", category: .teleporter)
                } else if letter == " " {  } else {
                    fatalError("Unknown letter: \(letter).")
                }
            }
        }
    }
    
    func createWall(position: CGPoint) {
        let node = SKSpriteNode(imageNamed: "block")
        node.position = position
        node.physicsBody = SKPhysicsBody(rectangleOf: node.size)
        node.physicsBody?.categoryBitMask = CollisionTypes.wall.rawValue
        node.physicsBody?.isDynamic = false
        addChild(node)
        mapNodes.append(node)
    }
    
    func createObject(position: CGPoint, name: String, category: CollisionTypes) {
        let node = SKSpriteNode(imageNamed: name)
        node.name = name
        node.position = position
        node.physicsBody = SKPhysicsBody(circleOfRadius: node.size.width / 2)
        node.physicsBody?.isDynamic = false
        node.physicsBody?.categoryBitMask = category.rawValue
        node.physicsBody?.contactTestBitMask = CollisionTypes.player.rawValue
        node.physicsBody?.collisionBitMask = 0
        if category == .vortex || category == .teleporter {
            node.run(SKAction.repeatForever(SKAction.rotate(byAngle: .pi, duration: 1)))
        }
        addChild(node)
        mapNodes.append(node)
        
        if category == .teleporter {
            if teleporters.0 == nil {
                teleporters.0 = node.position
            } else {
                teleporters.1 = node.position
            }
        }
    }
    
    func createPlayer(at position: CGPoint = CGPoint(x: 96, y: 672)) {
        player = SKSpriteNode(imageNamed: "player")
        player.position = position
        player.zPosition = 1
        player.physicsBody = SKPhysicsBody(circleOfRadius: player.size.width / 2)
        player.physicsBody?.allowsRotation = false
        player.physicsBody?.linearDamping = 0.5
        player.physicsBody?.categoryBitMask = CollisionTypes.player.rawValue
        player.physicsBody?.contactTestBitMask = CollisionTypes.star.rawValue | CollisionTypes.vortex.rawValue | CollisionTypes.teleporter.rawValue | CollisionTypes.finish.rawValue
        player.physicsBody?.collisionBitMask = CollisionTypes.wall.rawValue
        addChild(player)
    }
}

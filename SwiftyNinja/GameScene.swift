//
//  GameScene.swift
//  SwiftyNinja
//
//  Created by My Nguyen on 8/14/16.
//  Copyright (c) 2016 My Nguyen. All rights reserved.
//

import SpriteKit
import AVFoundation

enum ForceBomb {
    case Never, Always, Default
}
// one enemy that definitely is a bomb, one that might or might not be a bomb, two where one is a bomb
// and one isn't, then two/three/four random enemies, a chain of enemies, then a fast chain of enemies.
// The first two will be used exclusively when the player first starts the game, to give them a gentle
// warm up. After that, they'll be given random sequence types from TwoWithOneBomb to FastChain.
enum SequenceType: Int {
    case OneNoBomb, One, TwoWithOneBomb, Two, Three, Four, Chain, FastChain
}

class GameScene: SKScene {

    var gameScore: SKLabelNode!
    var score: Int = 0 {
        didSet {
            gameScore.text = "Score: \(score)"
        }
    }
    var livesImages = [SKSpriteNode]()
    var lives = 3
    // background slice in yellow
    var activeSliceBG: SKShapeNode!
    // foreground slice in white
    var activeSliceFG: SKShapeNode!
    // array of user's swipe points to keep track of all player moves on screen
    var activeSlicePoints = [CGPoint]()
    var swooshSoundActive = false
    var activeEnemies = [SKSpriteNode]()
    var bombSoundEffect: AVAudioPlayer!
    // the amount of time to wait between the last enemy being destroyed and a new one being created
    var popupTime = 0.9
    // an array of SequenceType enum that defines what enemies to create
    var sequence: [SequenceType]!
    // where we are right now in the game
    var sequencePosition = 0
    // how long to wait before creating a new enemy when the sequence type is .Chain or .FastChain
    var chainDelay = 3.0
    // indicate when all the enemies are destroyed so we can create more
    var nextSequenceQueued = true
    var gameEnded = false

    override func didMoveToView(view: SKView) {
        let background = SKSpriteNode(imageNamed: "sliceBackground")
        background.position = CGPoint(x: 512, y: 384)
        background.blendMode = .Replace
        background.zPosition = -1
        addChild(background)

        // CGVector represents Earth's gravity; CGVector can be visualized as a vector
        // with base at (0,0) and points to location (x,y). here the vector points straight down.
        physicsWorld.gravity = CGVector(dx: 0, dy: -6)
        // the speed is 0.85 which is slightly less than Earth's gravity of 0.98
        physicsWorld.speed = 0.85

        createScore()
        createLives()
        createSlices()

        // fill the sequence array with 7 pre-written sequences to help players warm up to the game
        sequence = [.OneNoBomb, .OneNoBomb, .TwoWithOneBomb, .TwoWithOneBomb, .Three, .One, .Chain]
        // add 1001 random sequence types to fill up the game
        for _ in 0 ... 1000 {
            let nextSequence = SequenceType(rawValue: RandomInt(min: 2, max: 7))!
            sequence.append(nextSequence)
        }

        // trigger the initial enemy toss after 2 seconds
        RunAfterDelay(2) { [unowned self] in
            self.tossEnemies()
        }
    }
    
    override func touchesBegan(touches: Set<UITouch>, withEvent event: UIEvent?) {
        super.touchesBegan(touches, withEvent: event)

        // remove all points in the activeSlicePoints array
        activeSlicePoints.removeAll(keepCapacity: true)

        if let touch = touches.first {
            // get the touch location and add it to the activeSlicePoints array
            let location = touch.locationInNode(self)
            activeSlicePoints.append(location)

            // clear the slice shapes
            redrawActiveSlice()

            // remove any actions currently attached to the slice shapes
            activeSliceBG.removeAllActions()
            activeSliceFG.removeAllActions()

            // make both slices fully visible
            activeSliceBG.alpha = 1
            activeSliceFG.alpha = 1
        }
    }
   
    override func touchesMoved(touches: Set<UITouch>, withEvent event: UIEvent?) {
        if gameEnded { return }
        
        // fetch the touch location
        guard let touch = touches.first else { return }
        let location = touch.locationInNode(self)

        // add the touch location to the slice points array
        activeSlicePoints.append(location)

        // redraw the slice shape
        redrawActiveSlice()

        if !swooshSoundActive {
            playSwooshSound()
        }

        let nodes = nodesAtPoint(location)
        for node in nodes {
            if node.name == "enemy" {
                /// destroy penguin
                // create a particle effect over the penguin
                let emitter = SKEmitterNode(fileNamed: "sliceHitEnemy")!
                emitter.position = node.position
                addChild(emitter)

                // clear its node name so that it can't be swiped repeatedly
                node.name = ""

                // disable the dynamic of its physics body so that it stops falling
                node.physicsBody!.dynamic = false

                // make the penguin fade out and scale out at the same time
                let scaleOut = SKAction.scaleTo(0.001, duration:0.2)
                let fadeOut = SKAction.fadeOutWithDuration(0.2)
                let group = SKAction.group([scaleOut, fadeOut])

                // remove the penguin from the scene
                let seq = SKAction.sequence([group, SKAction.removeFromParent()])
                node.runAction(seq)

                // increment player's score
                score += 1

                // remove the enemy from the activeEnemies array
                let index = activeEnemies.indexOf(node as! SKSpriteNode)!
                activeEnemies.removeAtIndex(index)

                // play a sound so the player knows they hit the penguin
                runAction(SKAction.playSoundFileNamed("whack.caf", waitForCompletion: false))
            } else if node.name == "bomb" {
                /// destroy bomb
                // the node called "bomb" is the bomb image, which is inside the bomb container.
                // so, we need to reference the node's parent when looking up our position,
                // changing the physics body, removing the node from the scene,
                // and removing the node from our activeEnemies array
                // note it's a different particle effect for bombs than for penguins
                let emitter = SKEmitterNode(fileNamed: "sliceHitBomb")!
                emitter.position = node.parent!.position
                addChild(emitter)

                node.name = ""
                node.parent!.physicsBody!.dynamic = false

                let scaleOut = SKAction.scaleTo(0.001, duration:0.2)
                let fadeOut = SKAction.fadeOutWithDuration(0.2)
                let group = SKAction.group([scaleOut, fadeOut])

                let seq = SKAction.sequence([group, SKAction.removeFromParent()])

                node.parent!.runAction(seq)

                let index = activeEnemies.indexOf(node.parent as! SKSpriteNode)!
                activeEnemies.removeAtIndex(index)

                runAction(SKAction.playSoundFileNamed("explosion.caf", waitForCompletion: false))

                // call endGame()
                endGame(triggeredByBomb: true)
            }
        }
    }

    // this method is invoked when the user finishes touching the screen
    override func touchesEnded(touches: Set<UITouch>, withEvent event: UIEvent?) {
        // fade out the slice shapes over .25 second
        activeSliceBG.runAction(SKAction.fadeOutWithDuration(0.25))
        activeSliceFG.runAction(SKAction.fadeOutWithDuration(0.25))
    }

    override func touchesCancelled(touches: Set<UITouch>?, withEvent event: UIEvent?) {
        if let touches = touches {
            // forward it to touchesEnded()
            touchesEnded(touches, withEvent: event)
        }
    }

    // this method is invoked at every frame before it's drawn: so we update the game state here
    override func update(currentTime: CFTimeInterval) {
        if activeEnemies.count > 0 {
            // if there's active enemies, loop through each of them
            for node in activeEnemies {
                if node.position.y < -140 {
                    node.removeAllActions()
                    if node.name == "enemy" {
                        // if the player misses slicing a penguin, they lose a life
                        node.name = ""
                        subtractLife()
                        node.removeFromParent()

                        if let index = activeEnemies.indexOf(node) {
                            activeEnemies.removeAtIndex(index)
                        }
                    } else if node.name == "bombContainer" {
                        // if the player slices a bomb, they lose all lives
                        node.name = ""
                        node.removeFromParent()

                        if let index = activeEnemies.indexOf(node) {
                            activeEnemies.removeAtIndex(index)
                        }
                    }
                }
            }
        } else {
            // if there's no active enemies
            if !nextSequenceQueued {
                // and there's no enemy sequence queued, then schedule the next enemy sequence
                RunAfterDelay(popupTime) { [unowned self] in
                    self.tossEnemies()
                }
                nextSequenceQueued = true
            }
        }

        // count the number of bomb containers in the game
        var bombCount = 0
        for node in activeEnemies {
            if node.name == "bombContainer" {
                bombCount += 1
                break
            }
        }

        // if there's no bomb, stop the fuse sound
        if bombCount == 0 {
            if bombSoundEffect != nil {
                bombSoundEffect.stop()
                bombSoundEffect = nil
            }
        }
    }

    func createScore() {
        gameScore = SKLabelNode(fontNamed: "Chalkduster")
        gameScore.text = "Score: 0"
        gameScore.horizontalAlignmentMode = .Left
        gameScore.fontSize = 48

        addChild(gameScore)

        gameScore.position = CGPoint(x: 8, y: 8)
    }

    func createLives() {
        for i in 0 ..< 3 {
            let spriteNode = SKSpriteNode(imageNamed: "sliceLife")
            spriteNode.position = CGPoint(x: CGFloat(834 + (i * 70)), y: 720)
            addChild(spriteNode)

            livesImages.append(spriteNode)
        }
    }

    // swiping around the screen will leave a glowing trail of slice marks that fade away
    // when you let go or keep moving
    func createSlices() {
        // draw 2 slice shapes which are placed above everything else in the game
        activeSliceBG = SKShapeNode()
        activeSliceBG.zPosition = 2
        activeSliceFG = SKShapeNode()
        activeSliceFG.zPosition = 2

        // the background slice is in yellow and the foreground in white
        // the background slice has a thicker line with than the foreground
        activeSliceBG.strokeColor = UIColor(red: 1, green: 0.9, blue: 0, alpha: 1)
        activeSliceBG.lineWidth = 9
        activeSliceFG.strokeColor = UIColor.whiteColor()
        activeSliceFG.lineWidth = 5

        addChild(activeSliceBG)
        addChild(activeSliceFG)
    }

    func redrawActiveSlice() {
        // if the activeSlicePoints array has less than 2 points,
        // then there's not enough data to draw a line
        if activeSlicePoints.count < 2 {
            activeSliceBG.path = nil
            activeSliceFG.path = nil
            return
        }

        // remove all slice points beyond the 12th, to keep the swipe shapes from becoming too long
        while activeSlicePoints.count > 12 {
            activeSlicePoints.removeAtIndex(0)
        }

        let path = UIBezierPath()
        // start the line at the first swipe point
        path.moveToPoint(activeSlicePoints[0])
        // then go through each other swipe point in activeSlicePoints
        for i in 1 ..< activeSlicePoints.count {
            path.addLineToPoint(activeSlicePoints[i])
        }

        // update the slice shape paths to draw them in their settings (line width and color)
        activeSliceBG.path = path.CGPath
        activeSliceFG.path = path.CGPath
    }

    func playSwooshSound() {
        // occupy this swoosh sound
        swooshSoundActive = true

        let randomNumber = RandomInt(min: 1, max: 3)
        let soundName = "swoosh\(randomNumber).caf"

        // waitForCompletion ensures the sound plays until completion;
        // so no other sound can play at the same time
        let swooshSound = SKAction.playSoundFileNamed(soundName, waitForCompletion: true)

        // reset swooshSoundActive so other swoosh sound can play
        runAction(swooshSound) { [unowned self] in
            self.swooshSoundActive = false
        }
    }

    func createEnemy(forceBomb forceBomb: ForceBomb = .Default) {
        var enemyType = RandomInt(min: 0, max: 6)
        if forceBomb == .Never {
            enemyType = 1
        } else if forceBomb == .Always {
            enemyType = 0
        }

        var enemy: SKSpriteNode
        if enemyType == 0 {
            /// position the bomb, which requires 3 components: a container, a bomb image,
            /// and a bomb fuse particle emitter,
            // create a new SKSpriteNode, the container for the fuse and the bomb image as children
            enemy = SKSpriteNode()
            // set the node's Z position to 1 so the bombs always appear in front of penguins
            enemy.zPosition = 1
            enemy.name = "bombContainer"

            // create a bomb image with the name "bomb"
            let bombImage = SKSpriteNode(imageNamed: "sliceBomb")
            bombImage.name = "bomb"
            // add the bomb image to the container
            enemy.addChild(bombImage)

            // if the bomb fuse sound effect is playing, stop it and destroy it
            if bombSoundEffect != nil {
                bombSoundEffect.stop()
                bombSoundEffect = nil
            }

            // create a new bomb fuse sound effect and play it; note AVAudioPlayer and not SKAction
            // is used for sound, so the sound can be stopped as needed
            let path = NSBundle.mainBundle().pathForResource("sliceBombFuse.caf", ofType:nil)!
            let url = NSURL(fileURLWithPath: path)
            let sound = try! AVAudioPlayer(contentsOfURL: url)
            bombSoundEffect = sound
            sound.play()

            // create a particle emitter node
            let emitter = SKEmitterNode(fileNamed: "sliceFuse")!
            // position the node at the end of the bomb image's fuse
            emitter.position = CGPoint(x: 76, y: 64)
            // add the node to the container
            enemy.addChild(emitter)
        } else {
            enemy = SKSpriteNode(imageNamed: "penguin")
            runAction(SKAction.playSoundFileNamed("launch.caf", waitForCompletion: false))
            enemy.name = "enemy"
        }

        /// position the enemy
        // set a random position off the screen's bottom edge
        let randomPosition = CGPoint(x: RandomInt(min: 64, max: 960), y: -128)
        enemy.position = randomPosition

        // create a random angular velocity (how fast something should spin)
        let randomAngularVelocity = CGFloat(RandomInt(min: -6, max: 6)) / 2.0

        // create a random X velocity (how far to move horizontally)
        var randomXVelocity = 0
        if randomPosition.x < 256 {
            randomXVelocity = RandomInt(min: 8, max: 15)
        } else if randomPosition.x < 512 {
            randomXVelocity = RandomInt(min: 3, max: 5)
        } else if randomPosition.x < 768 {
            randomXVelocity = -RandomInt(min: 3, max: 5)
        } else {
            randomXVelocity = -RandomInt(min: 8, max: 15)
        }

        // create a random Y velocity, to make things fly at different speeds
        let randomYVelocity = RandomInt(min: 24, max: 32)

        // give all enemies a circular physics body and a collisionBitMask so they don't collide
        enemy.physicsBody = SKPhysicsBody(circleOfRadius: 64)
        enemy.physicsBody!.velocity = CGVector(dx: randomXVelocity * 40, dy: randomYVelocity * 40)
        enemy.physicsBody!.angularVelocity = randomAngularVelocity
        enemy.physicsBody!.collisionBitMask = 0

        addChild(enemy)
        activeEnemies.append(enemy)
    }

    func tossEnemies() {
        if gameEnded { return }

        // every time this method is called, decrease both popupTime and chainDelay so the game
        // gets harder as they play
        popupTime *= 0.991
        chainDelay *= 0.99
        // also sneakily increase the speed of the physics world, so objects will rise and fall faster
        physicsWorld.speed *= 1.02

        let sequenceType = sequence[sequencePosition]
        switch sequenceType {
        // for the first 6 sequenceType, create one or more enemies
        // then wait for them to be destroyed before continuing
        case .OneNoBomb:
            createEnemy(forceBomb: .Never)

        case .One:
            createEnemy()

        case .TwoWithOneBomb:
            createEnemy(forceBomb: .Never)
            createEnemy(forceBomb: .Always)

        case .Two:
            createEnemy()
            createEnemy()

        case .Three:
            createEnemy()
            createEnemy()
            createEnemy()

        case .Four:
            createEnemy()
            createEnemy()
            createEnemy()
            createEnemy()

        // for the chain sequenceType, create 5 enemies with a short break in between
        // and don't wait for each one to be destroyed before continuing
        case .Chain:
            createEnemy()
            // a chain is made up of several enemies with a space between them, and the game
            // doesn't wait for an enmey to be sliced before showing the next thing in the chain
            RunAfterDelay(chainDelay / 5.0) { [unowned self] in self.createEnemy() }
            RunAfterDelay(chainDelay / 5.0 * 2) { [unowned self] in self.createEnemy() }
            RunAfterDelay(chainDelay / 5.0 * 3) { [unowned self] in self.createEnemy() }
            RunAfterDelay(chainDelay / 5.0 * 4) { [unowned self] in self.createEnemy() }

        case .FastChain:
            createEnemy()
            RunAfterDelay(chainDelay / 10.0) { [unowned self] in self.createEnemy() }
            RunAfterDelay(chainDelay / 10.0 * 2) { [unowned self] in self.createEnemy() }
            RunAfterDelay(chainDelay / 10.0 * 3) { [unowned self] in self.createEnemy() }
            RunAfterDelay(chainDelay / 10.0 * 4) { [unowned self] in self.createEnemy() }
        }

        sequencePosition += 1

        nextSequenceQueued = false
    }

    // this method is called when a penguin falls off the screen without being sliced
    func subtractLife() {
        // decement the lives property
        lives -= 1

        // play a sound indicating something bad happened
        runAction(SKAction.playSoundFileNamed("wrong.caf", waitForCompletion: false))

        // update the livesImages array so that the correct number are crossed off
        var life: SKSpriteNode
        if lives == 2 {
            life = livesImages[0]
        } else if lives == 1 {
            life = livesImages[1]
        } else {
            life = livesImages[2]
            // end the game if the player is out of lives
            endGame(triggeredByBomb: false)
        }

        // animate the life being lost
        life.texture = SKTexture(imageNamed: "sliceLifeGone")
        // set the X and Y scale of the life being lost to 1.3
        life.xScale = 1.3
        life.yScale = 1.3
        // animate it back down to 1.0
        life.runAction(SKAction.scaleTo(1, duration:0.1))
    }

    func endGame(triggeredByBomb triggeredByBomb: Bool) {
        if gameEnded {
            return
        }

        // the game hasn't ended
        gameEnded = true
        // stop every object from moving by adjusting the speed of the physics world to 0
        physicsWorld.speed = 0
        userInteractionEnabled = false

        // stop any bomb fuse fizzing
        if bombSoundEffect != nil {
            bombSoundEffect.stop()
            bombSoundEffect = nil
        }

        // set all 3 lives images to have the same "life gone" graphic
        if triggeredByBomb {
            livesImages[0].texture = SKTexture(imageNamed: "sliceLifeGone")
            livesImages[1].texture = SKTexture(imageNamed: "sliceLifeGone")
            livesImages[2].texture = SKTexture(imageNamed: "sliceLifeGone")
        }
    }
}

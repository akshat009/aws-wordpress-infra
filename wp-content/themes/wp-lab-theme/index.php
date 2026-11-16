<?php
/**
 * Main Template File for WP Lab Theme
 */
get_header(); ?>

<!DOCTYPE html>
<html <?php language_attributes(); ?>>
<head>
    <meta charset="<?php bloginfo( 'charset' ); ?>">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php bloginfo( 'name' ); ?> &bull; <?php bloginfo( 'description' ); ?></title>
    <link rel="stylesheet" href="<?php echo get_stylesheet_uri(); ?>">
    <?php wp_head(); ?>
</head>
<body <?php body_class(); ?>>

<header>
    <h1><?php bloginfo( 'name' ); ?></h1>
    <p><?php bloginfo( 'description' ); ?></p>
</header>

<main>
    <div class="cloud-badge">🚀 Deployed via Zero-Trust GitOps CI/CD</div>

    <?php
    if ( have_posts() ) :
        while ( have_posts() ) : the_post(); ?>
            <article id="post-<?php the_ID(); ?>" <?php post_class(); ?>>
                <h2><a href="<?php the_permalink(); ?>"><?php the_title(); ?></a></h2>
                <div class="entry-meta" style="color: #6b7280; font-size: 0.875rem; margin-bottom: 1rem;">
                    Published on <?php echo get_the_date(); ?> by <?php the_author(); ?>
                </div>
                <div class="entry-content">
                    <?php the_content(); ?>
                </div>
            </article>
        <?php endwhile;
    else : ?>
        <article>
            <h2>Welcome to your AWS WordPress Cloud Stack!</h2>
            <p>Your production Auto Scaling fleet, Application Load Balancer, and Amazon RDS MySQL database are fully connected and operating smoothly.</p>
        </article>
    <?php endif; ?>
</main>

<footer>
    <p>&copy; <?php echo date('Y'); ?> <?php bloginfo( 'name' ); ?> &bull; Powered by AWS & Terraform GitOps</p>
</footer>

<?php wp_footer(); ?>
</body>
</html>

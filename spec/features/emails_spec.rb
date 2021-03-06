require 'rails_helper'

feature 'Emails' do

  background do
    reset_mailer
  end

  scenario "Signup Email" do
    sign_up

    email = open_last_email
    expect(email).to have_subject('Confirmation instructions')
    expect(email).to deliver_to('manuela@madrid.es')
    expect(email).to have_body_text(user_confirmation_path)
  end

  scenario "Reset password" do
    reset_password

    email = open_last_email
    expect(email).to have_subject('Instructions for resetting your password')
    expect(email).to deliver_to('manuela@madrid.es')
    expect(email).to have_body_text(edit_user_password_path)
  end

  context 'Proposal comments' do
    scenario "Send email on proposal comment", :js do
      user = create(:user, email_on_comment: true)
      proposal = create(:proposal, author: user)
      comment_on(proposal)

      email = open_last_email
      expect(email).to have_subject('Someone has commented on your citizen proposal')
      expect(email).to deliver_to(proposal.author)
      expect(email).to have_body_text(proposal_path(proposal))
    end

    scenario 'Do not send email about own proposal comments', :js do
      user = create(:user, email_on_comment: true)
      proposal = create(:proposal, author: user)
      comment_on(proposal, user)

      expect { open_last_email }.to raise_error "No email has been sent!"
    end

    scenario 'Do not send email about proposal comment unless set in preferences', :js do
      user = create(:user, email_on_comment: false)
      proposal = create(:proposal, author: user)
      comment_on(proposal)

      expect { open_last_email }.to raise_error "No email has been sent!"
    end
  end

  context 'Debate comments' do
    scenario "Send email on debate comment", :js do
      user = create(:user, email_on_comment: true)
      debate = create(:debate, author: user)
      comment_on(debate)

      email = open_last_email
      expect(email).to have_subject('Someone has commented on your debate')
      expect(email).to deliver_to(debate.author)
      expect(email).to have_body_text(debate_path(debate))
      expect(email).to have_body_text(I18n.t("mailers.config.manage_email_subscriptions"))
      expect(email).to have_body_text(account_path)
    end

    scenario 'Do not send email about own debate comments', :js do
      user = create(:user, email_on_comment: true)
      debate = create(:debate, author: user)
      comment_on(debate, user)

      expect { open_last_email }.to raise_error "No email has been sent!"
    end

    scenario 'Do not send email about debate comment unless set in preferences', :js do
      user = create(:user, email_on_comment: false)
      debate = create(:debate, author: user)
      comment_on(debate)

      expect { open_last_email }.to raise_error "No email has been sent!"
    end
  end

  context 'Comment replies' do
    scenario "Send email on comment reply", :js do
      user = create(:user, email_on_comment_reply: true)
      reply_to(user)

      email = open_last_email
      expect(email).to have_subject('Someone has responded to your comment')
      expect(email).to deliver_to(user)
      expect(email).to_not have_body_text(debate_path(Comment.first.commentable))
      expect(email).to have_body_text(comment_path(Comment.last))
      expect(email).to have_body_text(I18n.t("mailers.config.manage_email_subscriptions"))
      expect(email).to have_body_text(account_path)
    end

    scenario "Do not send email about own replies to own comments", :js do
      user = create(:user, email_on_comment_reply: true)
      reply_to(user, user)

      expect { open_last_email }.to raise_error "No email has been sent!"
    end

    scenario "Do not send email about comment reply unless set in preferences", :js do
      user = create(:user, email_on_comment_reply: false)
      reply_to(user)

      expect { open_last_email }.to raise_error "No email has been sent!"
    end
  end

  scenario "Email depending on user's locale" do
    sign_up

    email = open_last_email
    expect(email).to have_subject('Confirmation instructions')
    expect(email).to deliver_to('manuela@madrid.es')
    expect(email).to have_body_text(user_confirmation_path)
  end

  scenario "Email on unfeasible spending proposal" do
    spending_proposal = create(:spending_proposal)
    administrator = create(:administrator)
    valuator = create(:valuator)
    spending_proposal.update(administrator: administrator)
    spending_proposal.valuators << valuator

    login_as(valuator.user)
    visit edit_valuation_spending_proposal_path(spending_proposal)

    choose  'spending_proposal_feasible_false'
    fill_in 'spending_proposal_feasible_explanation', with: 'This is not legal as stated in Article 34.9'
    check 'spending_proposal_valuation_finished'
    click_button 'Save changes'

    expect(page).to have_content "Dossier updated"
    spending_proposal.reload

    email = open_last_email
    expect(email).to have_subject("Your investment project '#{spending_proposal.code}' has been marked as unfeasible")
    expect(email).to deliver_to(spending_proposal.author.email)
    expect(email).to have_body_text(spending_proposal.title)
    expect(email).to have_body_text(spending_proposal.code)
    expect(email).to have_body_text(spending_proposal.feasible_explanation)
  end

  context "Direct Message" do

    scenario "Receiver email" do
      sender   = create(:user, :level_two)
      receiver = create(:user, :level_two)

      direct_message = create_direct_message(sender, receiver)

      email = unread_emails_for(receiver.email).first

      expect(email).to have_subject("You have received a new private message")
      expect(email).to have_body_text(direct_message.title)
      expect(email).to have_body_text(direct_message.body)
      expect(email).to have_body_text(direct_message.sender.name)
      expect(email).to have_body_text(/#{user_path(direct_message.sender_id)}/)
    end

    scenario "Sender email" do
      sender   = create(:user, :level_two)
      receiver = create(:user, :level_two)

      direct_message = create_direct_message(sender, receiver)

      email = unread_emails_for(sender.email).first

      expect(email).to have_subject("You have send a new private message")
      expect(email).to have_body_text(direct_message.title)
      expect(email).to have_body_text(direct_message.body)
      expect(email).to have_body_text(direct_message.receiver.name)
    end

    pending "In the copy sent to the sender, display the receiver's name"

  end

  context "Proposal notification digest" do

    scenario "notifications for proposals that I have supported" do
      user = create(:user, email_digest: true)

      proposal1 = create(:proposal)
      proposal2 = create(:proposal)
      proposal3 = create(:proposal)

      create(:vote, votable: proposal1, voter: user)
      create(:vote, votable: proposal2, voter: user)

      reset_mailer

      notification1 = create_proposal_notification(proposal1)
      notification2 = create_proposal_notification(proposal2)
      notification3 = create_proposal_notification(proposal3)

      email_digest = EmailDigest.new
      email_digest.create

      email = open_last_email
      expect(email).to have_subject("Proposal notifications in Consul")
      expect(email).to deliver_to(user.email)

      expect(email).to have_body_text(proposal1.title)
      expect(email).to have_body_text(notification1.notifiable.title)
      expect(email).to have_body_text(notification1.notifiable.body)
      expect(email).to have_body_text(proposal1.author.name)

      expect(email).to have_body_text(/#{notification_path(notification1)}/)
      expect(email).to have_body_text(/#{proposal_path(proposal1, anchor: 'comments')}/)
      expect(email).to have_body_text(/#{proposal_path(proposal1, anchor: 'social-share')}/)

      expect(email).to have_body_text(proposal2.title)
      expect(email).to have_body_text(notification2.notifiable.title)
      expect(email).to have_body_text(notification2.notifiable.body)
      expect(email).to have_body_text(/#{notification_path(notification2)}/)
      expect(email).to have_body_text(/#{proposal_path(proposal2, anchor: 'comments')}/)
      expect(email).to have_body_text(/#{proposal_path(proposal2, anchor: 'social-share')}/)
      expect(email).to have_body_text(proposal2.author.name)

      expect(email).to_not have_body_text(proposal3.title)
      expect(email).to have_body_text(/#{account_path}/)
    end

  end

end
